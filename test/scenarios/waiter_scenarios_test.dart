// Waiter scenarios at restaurant scale (130 tables, ~300 items, slow/lost/offline
// network). They always run and assert; with SCREENSHOT_DIR set they also
// render 1080x2340 PNGs:
//   SCREENSHOT_DIR=/home/claude/work/out/waiter_review flutter test test/scenarios
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servepos_waiter/core/api/api_exception.dart';
import 'package:servepos_waiter/features/order/take_order_screen.dart';

import 'harness.dart';

const prefix = 'after';

/// Floor → "Find table" → type → tap the result.
Future<void> findTable(Harness h, String table, {String? typed}) async {
  await h.tap(find.byKey(const Key('floor_find')), note: 'Find table');
  await h.wait(const Duration(milliseconds: 400));
  await h.type(find.byKey(const Key('find_table_field')), typed ?? table);
  await h.wait(const Duration(milliseconds: 200));
  await h.tap(find.byKey(Key('find_$table')), note: 'result $table');
  await h.wait(const Duration(milliseconds: 600));
}

Future<void> addItem(Harness h, String query, String code, {List<String> mods = const [], int extra = 0}) async {
  final search = find.byKey(const Key('menu_search'));
  await h.tap(search, note: 'search box');
  await h.type(search, query);
  await h.wait(const Duration(milliseconds: 200));
  var swipes = 0;
  while (find.byKey(Key('item_$code')).evaluate().isEmpty && swipes < 20) {
    await h.tester.drag(find.byType(GridView).first, const Offset(0, -400));
    await h.tester.pump(const Duration(milliseconds: 300));
    swipes++;
    h.taps++;
  }
  if (swipes > 0) h.log.add('swipes to find $code in results: $swipes');
  await h.tap(find.byKey(Key('item_$code')), note: 'item $code');
  await h.wait(const Duration(milliseconds: 500));
  if (find.byKey(const Key('mod_add')).evaluate().isNotEmpty) {
    for (final m in mods) {
      await h.tap(find.byKey(Key('mod_$m')), note: 'option $m');
    }
    for (var i = 0; i < extra; i++) {
      await h.tap(find.bySemanticsLabel('plus').last, note: 'qty +');
    }
    await h.tap(find.byKey(const Key('mod_add')), note: 'add to order');
    await h.wait(const Duration(milliseconds: 500));
  }
}

Future<void> takeA12Order(Harness h) async {
  await addItem(h, 'karak', 'KARAK', mods: ['Sugar_Less sugar'], extra: 1);
  await addItem(h, 'spanish latte', 'LATTE', mods: ['Milk_Oat milk', 'Size_Large', 'Extras_Extra shot']);
  await addItem(h, 'wagyu', 'BURGER', mods: ['Cook_Medium', 'Side_Sweet potato fries']);
  await addItem(h, 'water', 'WATER');
  FocusManager.instance.primaryFocus?.unfocus();
  await h.wait(const Duration(milliseconds: 300));
}

bool onFloor() => find.byType(TakeOrderScreen).evaluate().isEmpty;
bool showsText(String t) => find.textContaining(t).evaluate().isNotEmpty;

void main() {
  testWidgets('S1 slow network (3 s): Send tapped 5 times -> one order, clear result', (tester) async {
    final h = await boot(tester);
    h.api.latency = const Duration(seconds: 3);
    await h.shot('${prefix}_s1_01_floor');
    await findTable(h, 'A12');
    await takeA12Order(h);
    await h.shot('${prefix}_s1_02_cart_ready');
    final tapsToBuild = h.taps;
    for (var i = 0; i < 5; i++) {
      await h.tap(find.byKey(const Key('cart_send')), note: 'SEND #${i + 1}');
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(find.byKey(const Key('sending_lock')), findsOneWidget, reason: 'cart locked, "Sending…" shown at once');
    expect(showsText('Sending to the till'), isTrue);
    await h.shot('${prefix}_s1_03_sending');
    await h.wait(const Duration(milliseconds: 2700));
    expect(find.byKey(const Key('send_result')), findsOneWidget);
    expect(showsText('Sent to the till'), isTrue);
    expect(find.byKey(const Key('result_order_no')), findsOneWidget);
    expect(showsText('A12 · Section A'), isTrue);
    expect(showsText('5'), isTrue);
    await h.shot('${prefix}_s1_04_result');
    await h.wait(const Duration(seconds: 3));
    expect(onFloor(), isTrue, reason: 'back on the floor');
    expect(find.byKey(const Key('send_result')), findsNothing, reason: 'success dismisses itself');
    await h.shot('${prefix}_s1_05_floor_after');
    report('S1', h, {
      'tapsToBuild': tapsToBuild,
      'createRequests': h.api.createRequests,
      'ordersOnServer': h.api.orderCount,
      'feedback': h.feedback.events,
    });
    expect(h.api.createRequests, 1);
    expect(h.api.orderCount, 1);
    expect(h.feedback.events, ['sending', 'sent']);
    expect(h.services.floor.live('A12')!.order, isNotNull);
    await h.dispose();
  });

  testWidgets('S2 response lost: Try again reuses the id; re-entering is caught', (tester) async {
    final h = await boot(tester);
    h.api.latency = const Duration(seconds: 3);
    h.api.loseResponses = 1;
    await findTable(h, 'A12');
    await takeA12Order(h);
    await h.tap(find.byKey(const Key('cart_send')), note: 'SEND');
    await h.wait(const Duration(milliseconds: 3200));
    expect(showsText('No answer from the till yet'), isTrue);
    expect(showsText('Do not enter it again'), isTrue);
    await h.shot('${prefix}_s2_01_no_answer');
    expect(h.api.orderCount, 1, reason: 'the server did create it');
    await h.tap(find.byKey(const Key('result_retry')), note: 'Try again now');
    await h.wait(const Duration(milliseconds: 3200));
    expect(showsText('Sent to the till'), isTrue);
    await h.shot('${prefix}_s2_02_retry_same_id_sent');
    await h.tap(find.byKey(const Key('result_ok')), note: 'OK');
    await h.wait(const Duration(milliseconds: 400));
    // A waiter who still doubts it enters the same items again.
    await findTable(h, 'A12');
    await takeA12Order(h);
    await h.tap(find.byKey(const Key('cart_send')), note: 'SEND same items again');
    await h.wait(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('dup_dialog')), findsOneWidget);
    await h.shot('${prefix}_s2_03_send_again_question');
    await h.tap(find.byKey(const Key('dup_cancel')), note: "Don't send");
    await h.wait(const Duration(milliseconds: 400));
    report('S2', h, {
      'createRequests': h.api.createRequests,
      'distinctRequestIds': h.api.distinctRequestIds.length,
      'ordersOnServer': h.api.orderCount,
    });
    expect(h.api.createRequests, 2);
    expect(h.api.distinctRequestIds.length, 1, reason: 'retry used the same client_request_id');
    expect(h.api.orderCount, 1);
    expect(h.services.carts.peek('table:A12')!.itemCount, 5, reason: 'the doubtful re-entry stays a draft');
    await h.dispose();
  });

  testWidgets('S3 offline: queued with badge, back online -> sent once', (tester) async {
    final h = await boot(tester);
    await findTable(h, 'A12');
    await takeA12Order(h);
    h.api.offline = true;
    h.services.net.report(false);
    await h.tap(find.byKey(const Key('cart_send')), note: 'SEND offline');
    await h.wait(const Duration(milliseconds: 600));
    expect(showsText('Not sent yet'), isTrue);
    expect(showsText('will send by itself'), isTrue);
    await h.shot('${prefix}_s3_01_send_offline');
    await h.tap(find.byKey(const Key('result_keep')), note: 'Keep for later');
    await h.wait(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('outbox_waiting_strip')), findsOneWidget);
    expect(showsText('Waiting to send'), isTrue);
    await h.shot('${prefix}_s3_02_floor_waiting_badge');
    await h.tap(find.text('Orders').last, note: 'Orders tab');
    await h.wait(const Duration(milliseconds: 500));
    await h.shot('${prefix}_s3_03_orders_on_this_phone');
    await h.tap(find.text('Floor').last, note: 'Floor tab');
    await h.wait(const Duration(milliseconds: 300));
    h.api.offline = false;
    h.api.latency = const Duration(milliseconds: 200);
    h.services.net.report(true); // back online -> flush
    h.services.outbox.flush(force: true); // app resume at the same moment
    h.services.outbox.flush(force: true);
    await h.wait(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('toast')), findsOneWidget);
    expect(showsText('A12: sent to the till'), isTrue);
    await h.shot('${prefix}_s3_04_back_online_sent');
    report('S3', h, {'createRequests': h.api.createRequests, 'ordersOnServer': h.api.orderCount, 'outboxLeft': h.services.outbox.count});
    expect(h.api.createRequests, 1);
    expect(h.api.orderCount, 1);
    expect(h.services.outbox.count, 0);
    await h.wait(const Duration(seconds: 5));
    await h.dispose();
  });

  testWidgets('S4 second round while the first is still sending (10 s network)', (tester) async {
    final h = await boot(tester);
    h.api.latency = const Duration(seconds: 10);
    await findTable(h, 'A12');
    await takeA12Order(h);
    await h.tap(find.byKey(const Key('cart_send')), note: 'SEND round 1');
    await h.wait(const Duration(seconds: 1));
    await h.tap(find.byKey(const Key('lock_back')), note: 'back while sending');
    await h.wait(const Duration(milliseconds: 400));
    expect(showsText('Sending…'), isTrue, reason: 'floor tile shows Sending');
    await h.shot('${prefix}_s4_01_floor_while_sending');
    await findTable(h, 'A12');
    expect(find.byKey(const Key('sending_lock')), findsOneWidget, reason: 'same table: still locked, no second order possible');
    await h.shot('${prefix}_s4_02_reopen_locked');
    await h.wait(const Duration(seconds: 9));
    expect(showsText('Sent to the till'), isTrue);
    await h.tap(find.byKey(const Key('result_ok')), note: 'OK');
    await h.wait(const Duration(milliseconds: 500));
    // Still on A12 (reopened screen unlocks): round 2 goes to the now-open order.
    expect(find.byType(TakeOrderScreen), findsOneWidget);
    expect(find.byKey(const Key('sending_lock')), findsNothing);
    await addItem(h, 'water', 'WATER');
    FocusManager.instance.primaryFocus?.unfocus();
    await h.tap(find.byKey(const Key('cart_send')), note: 'SEND round 2');
    await h.wait(const Duration(seconds: 10, milliseconds: 300));
    expect(showsText('Added to the order'), isTrue);
    await h.shot('${prefix}_s4_03_round2_added');
    report('S4', h, {
      'createRequests': h.api.createRequests,
      'addRequests': h.api.addRequests,
      'ordersForA12': h.api.ordersByName.values.where((o) => o['table'] == 'A12').length,
    });
    expect(h.api.createRequests, 1);
    expect(h.api.addRequests, 1);
    expect(h.api.ordersByName.values.where((o) => o['table'] == 'A12').length, 1);
    await h.wait(const Duration(seconds: 3));
    await h.dispose();
  });

  testWidgets('S4b round 2 while round 1 is unconfirmed (lost answer) -> one order, two rounds', (tester) async {
    final h = await boot(tester);
    h.api.latency = const Duration(seconds: 3);
    h.api.loseResponses = 1;
    await findTable(h, 'A12');
    await addItem(h, 'karak', 'KARAK', mods: ['Sugar_Normal']);
    FocusManager.instance.primaryFocus?.unfocus();
    await h.tap(find.byKey(const Key('cart_send')), note: 'SEND round 1');
    await h.wait(const Duration(milliseconds: 3200));
    await h.tap(find.byKey(const Key('result_keep')), note: 'Keep for later');
    await h.wait(const Duration(milliseconds: 400));
    await findTable(h, 'A12');
    await addItem(h, 'water', 'WATER');
    FocusManager.instance.primaryFocus?.unfocus();
    await h.tap(find.byKey(const Key('cart_send')), note: 'SEND round 2');
    await h.wait(const Duration(milliseconds: 400));
    expect(showsText('Saved, waits for round 1'), isTrue);
    await h.shot('${prefix}_s4b_01_round2_waits');
    await h.tap(find.byKey(const Key('result_keep')), note: 'Keep');
    await h.wait(const Duration(milliseconds: 300));
    h.services.outbox.flush(force: true);
    await h.wait(const Duration(seconds: 8));
    final a12 = h.api.ordersByName.entries.where((e) => e.value['table'] == 'A12').toList();
    report('S4b', h, {'ordersForA12': a12.length, 'rounds': a12.isEmpty ? 0 : h.api.roundsOf(a12.first.key)});
    expect(a12.length, 1);
    expect(h.api.roundsOf(a12.first.key), 2);
    expect(h.services.outbox.count, 0);
    await h.wait(const Duration(seconds: 9));
    await h.dispose();
  });

  testWidgets('S5 drafts per table, back and forth', (tester) async {
    final h = await boot(tester);
    await findTable(h, 'A12');
    await addItem(h, 'karak', 'KARAK', mods: ['Sugar_Normal']);
    await h.tap(find.byTooltip('Back'), note: 'back');
    await h.wait(const Duration(milliseconds: 400));
    await findTable(h, 'B3');
    await addItem(h, 'water', 'WATER');
    await h.tap(find.byTooltip('Back'), note: 'back');
    await h.wait(const Duration(milliseconds: 400));
    await h.shot('${prefix}_s5_01_floor_two_drafts');
    await findTable(h, 'A12');
    final keptA12 = h.services.carts.peek('table:A12')?.itemCount ?? 0;
    await h.tap(find.byKey(const Key('cart_send')), note: 'SEND');
    await h.wait(const Duration(seconds: 3));
    await h.tap(find.text('Section A').first, note: 'Section A');
    await h.wait(const Duration(milliseconds: 400));
    await h.shot('${prefix}_s5_02_floor_after_send');
    report('S5', h, {
      'a12DraftKept': keptA12,
      'a12DraftAfterSend': h.services.carts.peek('table:A12')?.itemCount ?? 0,
      'b3DraftKept': h.services.carts.peek('table:B3')?.itemCount ?? 0,
      'a12Occupied': h.services.floor.live('A12')?.order != null,
    });
    expect(keptA12, 1);
    expect(h.services.carts.peek('table:A12')?.itemCount ?? 0, 0);
    expect(h.services.carts.peek('table:B3')!.itemCount, 1);
    expect(h.services.floor.live('A12')!.order, isNotNull);
    expect(showsText('Sent '), isTrue, reason: 'A12 tile shows Sent hh:mm');
    await h.dispose();
  });

  testWidgets('S6 find B20B among 130 tables; tap targets', (tester) async {
    final h = await boot(tester);
    await h.shot('${prefix}_s6_01_floor_130');
    await h.tap(find.byKey(const Key('floor_find')), note: 'Find table');
    await h.wait(const Duration(milliseconds: 400));
    await h.type(find.byKey(const Key('find_table_field')), '20b');
    await h.wait(const Duration(milliseconds: 200));
    await h.shot('${prefix}_s6_02_find_b20b');
    await h.tap(find.byKey(const Key('find_B20B')), note: 'B20B');
    await h.wait(const Duration(milliseconds: 600));
    expect(find.text('B20B'), findsWidgets);
    final tapsToB20B = h.taps;
    await h.tap(find.byTooltip('Back'));
    await h.wait(const Duration(milliseconds: 400));
    // Room switch starts at the top of the new room.
    await h.tap(find.text('Section B').first, note: 'Section B');
    await h.wait(const Duration(milliseconds: 400));
    expect(find.text('B1'), findsOneWidget);
    final small = <String>[];
    for (final e in find.byWidgetPredicate((w) => w is InkWell && w.onTap != null).evaluate()) {
      final box = e.renderObject as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final s = box.size;
      if (s.width < 48 || s.height < 48) small.add('${e.widget.runtimeType} ${s.width.toStringAsFixed(0)}x${s.height.toStringAsFixed(0)}');
    }
    await h.shot('${prefix}_s6_03_section_b_top');
    report('S6', h, {'tapsToB20B': tapsToB20B, 'smallTargetsOnFloor': small});
    expect(tapsToB20B, lessThanOrEqualTo(5));
    expect(small, isEmpty);
    await h.dispose();
  });

  testWidgets('S7 guest call while taking an order', (tester) async {
    final h = await boot(tester);
    await findTable(h, 'A12');
    await addItem(h, 'karak', 'KARAK', mods: ['Sugar_Normal']);
    FocusManager.instance.primaryFocus?.unfocus();
    h.api.callsJson = [
      {
        'name': 'CALL-0101',
        'table': 'B20B',
        'room': 'Section B',
        'created': '2026-10-26 12:00:00',
        'status': 'Accepted',
        'accepted_by': 'Sara',
        'guest_note': null,
      },
    ];
    await h.services.calls.refresh(); // first load
    h.api.callsJson = [
      ...h.api.callsJson,
      {
        'name': 'CALL-0102',
        'table': 'C7',
        'room': 'Section C',
        'created': '2026-10-26 12:01:00',
        'status': 'Open',
        'accepted_by': null,
        'guest_note': 'Bill please',
      },
    ];
    await h.services.calls.refresh();
    await h.wait(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('call_banner')), findsOneWidget);
    expect(showsText('C7 is calling'), isTrue);
    await h.shot('${prefix}_s7_01_call_during_order');
    h.api.callsJson = [
      for (final c in h.api.callsJson) c['name'] == 'CALL-0102' ? {...c, 'status': 'Accepted', 'accepted_by': 'Ahmed'} : c,
    ];
    await h.tap(find.byKey(const Key('call_banner_go')), note: "I'm going");
    await h.wait(const Duration(milliseconds: 500));
    await h.shot('${prefix}_s7_02_after_accept');
    report('S7', h, {
      'alertsRung': h.alerts.shown,
      'accepted': h.api.calls.contains('accept CALL-0102'),
      'draftKept': h.services.carts.peek('table:A12')?.itemCount ?? 0,
    });
    expect(h.api.calls, contains('accept CALL-0102'));
    expect(find.byKey(const Key('call_banner')), findsNothing);
    expect(find.byType(TakeOrderScreen), findsOneWidget, reason: 'still on the order');
    expect(h.services.carts.peek('table:A12')!.itemCount, 1);
    await h.dispose();
  });

  testWidgets('S8 order accepted then ready: seen and heard without push', (tester) async {
    final h = await boot(tester);
    h.services.orders.startPolling();
    await findTable(h, 'A12');
    await addItem(h, 'water', 'WATER');
    FocusManager.instance.primaryFocus?.unfocus();
    await h.tap(find.byKey(const Key('cart_send')), note: 'SEND');
    await h.wait(const Duration(seconds: 4));
    final name = h.api.ordersByName.keys.first;
    await h.wait(const Duration(seconds: 16)); // a poll learns "Sent"
    h.api.setStatus(name, 'Accepted');
    expect(await h.waitFor(find.textContaining('A12: accepted at the till'), max: const Duration(seconds: 16)), isTrue);
    await h.wait(const Duration(milliseconds: 300));
    await h.shot('${prefix}_s8_01_accepted_toast');
    await h.wait(const Duration(seconds: 5));
    h.api.setStatus(name, 'Ready');
    expect(await h.waitFor(find.textContaining('A12 is ready to serve'), max: const Duration(seconds: 16)), isTrue);
    await h.wait(const Duration(milliseconds: 300));
    await h.shot('${prefix}_s8_02_ready_toast');
    await h.wait(const Duration(seconds: 9));
    await h.tap(find.text('Orders').last, note: 'Orders tab');
    await h.wait(const Duration(milliseconds: 600));
    await h.shot('${prefix}_s8_03_orders_ready');
    report('S8', h, {'alerts': h.alerts.shown});
    expect(h.alerts.shown, contains('order:order_ready:$name'));
    await h.dispose();
  });

  testWidgets('S9 Arabic RTL: scenario 1', (tester) async {
    final h = await boot(tester, language: 'ar');
    h.api.latency = const Duration(seconds: 3);
    await h.shot('${prefix}_s9_01_floor_ar');
    await findTable(h, 'A12');
    await takeA12Order(h);
    await h.tap(find.byKey(const Key('cart_review')), note: 'review');
    await h.wait(const Duration(milliseconds: 600));
    await h.shot('${prefix}_s9_02_review_ar');
    await h.tap(find.byKey(const Key('sheet_send')), note: 'send from review');
    await h.tap(find.byKey(const Key('cart_send')), note: 'send again quickly');
    await h.wait(const Duration(milliseconds: 300));
    await h.shot('${prefix}_s9_03_sending_ar');
    await h.wait(const Duration(seconds: 3));
    expect(showsText('أُرسل إلى الكاشير'), isTrue);
    await h.shot('${prefix}_s9_04_result_ar');
    report('S9', h, {'ordersOnServer': h.api.orderCount, 'createRequests': h.api.createRequests});
    expect(h.api.createRequests, 1);
    await h.wait(const Duration(seconds: 3));
    await h.dispose();
  });

  testWidgets('S10 refused by the till: says why, Edit returns the draft', (tester) async {
    final h = await boot(tester);
    await findTable(h, 'A12');
    await addItem(h, 'water', 'WATER');
    FocusManager.instance.primaryFocus?.unfocus();
    h.api.createError = const ServerException('Item Still Water is not available today', statusCode: 417);
    await h.tap(find.byKey(const Key('cart_send')), note: 'SEND');
    await h.wait(const Duration(milliseconds: 500));
    expect(showsText('Not sent: the till refused it'), isTrue);
    expect(showsText('Item Still Water is not available today'), isTrue);
    expect(find.byType(TakeOrderScreen), findsOneWidget);
    await h.shot('${prefix}_s10_01_refused');
    await h.tap(find.byKey(const Key('result_edit')), note: 'Edit order');
    await h.wait(const Duration(milliseconds: 400));
    report('S10', h, {'draftBack': h.services.carts.peek('table:A12')?.itemCount ?? 0});
    expect(h.services.carts.peek('table:A12')!.itemCount, 1);
    expect(h.services.outbox.count, 0);
    expect(h.services.sending.currentResult, isNull);
    expect(h.feedback.events.last, 'failed');
    await h.dispose();
  });
}
