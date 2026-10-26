import 'package:flutter_test/flutter_test.dart';
import 'package:servepos_waiter/core/alerts.dart';
import 'package:servepos_waiter/core/api/api_exception.dart';
import 'package:servepos_waiter/features/order/cart.dart';
import 'package:servepos_waiter/features/order/order_sender.dart';
import 'package:servepos_waiter/features/order/outbox.dart';
import 'package:servepos_waiter/features/order/send_controller.dart';
import 'package:servepos_waiter/features/order/take_order_screen.dart' show rankedSearch;
import 'package:servepos_waiter/features/orders/orders_controller.dart';

import 'scenarios/harness.dart' show ScenarioApi, bigMenu;
import 'support/fakes.dart';

void main() {
  late ScenarioApi api;
  late CartStore carts;
  late Outbox outbox;
  late OrderSender sender;
  late SendController send;
  late RecordingFeedback feedback;
  late DateTime now;
  final menu = bigMenu();
  CartLine line(String code, {int qty = 1}) => CartLine.fromItem(menu.items.firstWhere((i) => i.itemCode == code), qty: qty);
  const a12 = CartTarget.table(table: 'A12', room: 'Section A', tableLabel: 'A12');

  setUp(() {
    now = DateTime(2026, 10, 26, 13);
    api = ScenarioApi()..latency = const Duration(milliseconds: 40);
    carts = CartStore();
    outbox = Outbox(sender: OrderSender.senderFor(api))..currentUser = 'ahmed@example.com';
    sender = OrderSender(carts: carts, outbox: outbox);
    feedback = RecordingFeedback();
    send = SendController(sender: sender, outbox: outbox, feedback: feedback, clock: () => now);
    outbox.onSent = send.onOutboxSent;
  });

  Future<SendJob> submit({String? existing}) =>
      send.submit(target: a12, posProfile: 'P', user: 'ahmed@example.com', existingOrder: existing);

  test('5 rapid taps on Send -> 1 API call, one job, one order', () async {
    carts.add(a12.key, line('KARAK', qty: 2));
    carts.add(a12.key, line('WATER'));
    final futures = [for (var i = 0; i < 5; i++) submit()];
    expect(send.sendingFor(a12.key), isNotNull, reason: 'locked from the first tap');
    final jobs = await Future.wait(futures);
    expect(jobs.toSet().length, 1);
    expect(api.createRequests, 1);
    expect(api.orderCount, 1);
    expect(jobs.first.phase, SendPhase.sent);
    expect(jobs.first.order!.name, startsWith('WO-'));
    expect(feedback.events, ['sending', 'sent']);
    expect(carts.peek(a12.key)?.isEmpty ?? true, isTrue);
  });

  test('response lost: retry reuses the same client_request_id, one order', () async {
    api.loseResponses = 1;
    carts.add(a12.key, line('WATER'));
    final job = await submit();
    expect(job.phase, SendPhase.queued);
    expect(job.maybeArrived, isTrue);
    expect(api.orderCount, 1, reason: 'the server did create it');
    final again = await send.retry(job.id);
    expect(again.phase, SendPhase.sent);
    expect(api.createRequests, 2);
    expect(api.distinctRequestIds, {job.id});
    expect(api.orderCount, 1);
    expect(outbox.count, 0);
  });

  test('offline -> queued -> back online -> sent once, even with three flushes at once', () async {
    api.offline = true;
    carts.add(a12.key, line('WATER'));
    final job = await submit();
    expect(job.phase, SendPhase.queued);
    expect(job.offline, isTrue);
    expect(outbox.waitingCount, 1);
    api.offline = false;
    await Future.wait([outbox.flush(force: true), outbox.flush(force: true), outbox.send(job.id)]);
    expect(api.createRequests, 1);
    expect(api.orderCount, 1);
    expect(outbox.count, 0);
    expect(send.recent.first.phase, SendPhase.sent);
    expect(send.currentResult!.background, isTrue, reason: 'background send shows a toast');
  });

  test('a second send() of an entry on the wire joins it instead of sending again', () async {
    carts.add(a12.key, line('WATER'));
    final e = OutboxEntry(
      id: 'X1',
      kind: OutboxKind.create,
      payload: {'client_request_id': 'X1', 'table': 'A12', 'items': carts.cartFor(a12.key).toPayloadItems()},
      user: 'ahmed@example.com',
      label: 'A12',
      cartKey: a12.key,
      total: 6,
      itemCount: 1,
      lines: const [],
      createdAt: now,
    );
    await outbox.enqueue(e);
    final a = outbox.send('X1');
    final b = outbox.send('X1');
    expect(identical(a, b), isTrue);
    final ra = await a;
    expect(ra, isA<SentOutcome>());
    expect(api.createRequests, 1);
  });

  test('round 2 while round 1 is unconfirmed: waits, then goes as add_items to the same order', () async {
    api.loseResponses = 1;
    carts.add(a12.key, line('KARAK'));
    final r1 = await submit();
    expect(r1.phase, SendPhase.queued);
    carts.add(a12.key, line('WATER'));
    final r2 = await submit();
    expect(r2.phase, SendPhase.queued);
    expect(r2.waitingForFirstRound, isTrue);
    expect(r2.isRound, isTrue);
    expect(outbox.isAnySending, isFalse, reason: 'no stale in-flight entry left behind');
    await outbox.flush(force: true);
    expect(api.ordersByName.values.where((o) => o['table'] == 'A12').length, 1);
    expect(api.roundsOf(api.ordersByName.keys.single), 2);
    expect(outbox.count, 0);
  });

  test('same items to the same table within 2 minutes asks "Send again?"', () async {
    carts.add(a12.key, line('WATER', qty: 2));
    final sig = SendController.signatureOf(carts.cartFor(a12.key));
    final job = await submit();
    expect(job.phase, SendPhase.sent);
    carts.add(a12.key, line('WATER', qty: 2));
    final hit = send.duplicateOf(a12.key, SendController.signatureOf(carts.cartFor(a12.key)));
    expect(SendController.signatureOf(carts.cartFor(a12.key)), sig);
    expect(hit, isNotNull);
    expect(hit!.orderName, job.order!.name);
    expect(send.duplicateOf(a12.key, SendController.signatureOf(TableCart(key: 'x', lines: [line('KARAK')]))), isNull,
        reason: 'different items are a normal next round');
    expect(send.duplicateOf('table:B3', sig), isNull, reason: 'other table');
    now = now.add(const Duration(minutes: 3));
    expect(send.duplicateOf(a12.key, sig), isNull, reason: 'older than 2 minutes');
  });

  test('same items still unsent on this phone also count as a duplicate', () async {
    api.offline = true;
    carts.add(a12.key, line('WATER'));
    await submit();
    carts.add(a12.key, line('WATER'));
    final hit = send.duplicateOf(a12.key, SendController.signatureOf(carts.cartFor(a12.key)));
    expect(hit?.stillUnsent, isTrue);
  });

  test('refused: kept as Not sent; Retry keeps the id; Edit returns the draft', () async {
    api.createError = const ServerException('Table is closed', statusCode: 417);
    carts.add(a12.key, line('WATER'));
    final job = await submit();
    expect(job.phase, SendPhase.failed);
    expect(feedback.events.last, 'failed');
    expect(outbox.failedCount, 1);
    final again = await send.retry(job.id);
    expect(again.id, job.id);
    expect(again.phase, SendPhase.failed);
    await send.editDraft(again);
    expect(outbox.count, 0);
    expect(carts.cartFor(a12.key).itemCount, 1);
    expect(send.currentResult, isNull);
  });

  test('flush skips entries removed while it runs (no "No outbox entry" crash)', () async {
    api.offline = true;
    carts.add(a12.key, line('WATER'));
    final j1 = await submit();
    const b3 = CartTarget.table(table: 'B3');
    carts.add(b3.key, line('KARAK'));
    await send.submit(target: b3, posProfile: 'P', user: 'ahmed@example.com');
    api.offline = false;
    final f = outbox.flush(force: true);
    await outbox.remove(outbox.entries.firstWhere((e) => e.id != j1.id).id);
    await f;
    expect(api.createRequests, 1);
  });

  test('reconcile: draft lines already saved in the outbox are not sent twice after a crash', () async {
    api.offline = true;
    final l = line('WATER');
    carts.add(a12.key, l);
    await submit();
    // Crash between "saved to outbox" and "draft cleared": the draft comes back.
    carts.restore(a12.key, [CartLine.fromJson(l.toJson())]);
    expect(carts.cartFor(a12.key).itemCount, 1);
    sender.reconcile();
    expect(carts.cartFor(a12.key).itemCount, 0);
  });

  test('menu search puts the exact match first', () {
    final r = rankedSearch(menu.items, 'karak');
    expect(r.first.itemCode, 'KARAK');
    expect(r.length, greaterThan(20));
  });

  test('orders polling reports Accepted and Ready changes', () async {
    final fake = FakeWaiterApi()..ordersJson = [orderJson(name: 'WO-1', status: 'Pending', table: 'A12')];
    final alerts = NoopAlerts();
    final c = OrdersController(api: fake, alerts: alerts)..profile = 'P';
    final seen = <String>[];
    c.onStatusChange = (o, from) => seen.add('${o.name}:${from.wire}->${o.status.wire}');
    await c.refresh();
    fake.ordersJson = [orderJson(name: 'WO-1', status: 'Accepted', table: 'A12')];
    await c.refresh();
    fake.ordersJson = [orderJson(name: 'WO-1', status: 'Ready', table: 'A12')];
    await c.refresh();
    expect(seen, ['WO-1:Pending->Accepted', 'WO-1:Accepted->Ready']);
    expect(alerts.shown, contains('order:order_ready:WO-1'));
    c.startPolling(every: const Duration(milliseconds: 20));
    final before = fake.calls.where((x) => x == 'orders').length;
    await Future<void>.delayed(const Duration(milliseconds: 90));
    c.stopPolling();
    expect(fake.calls.where((x) => x == 'orders').length, greaterThan(before));
  });
}
