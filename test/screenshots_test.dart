// Renders the main screens to PNG with the real fonts, for review.
// Run: SCREENSHOT_DIR=/path flutter test test/screenshots_test.dart
// Skipped when SCREENSHOT_DIR is not set.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servepos_waiter/app/app.dart';
import 'package:servepos_waiter/app/services.dart';
import 'package:servepos_waiter/core/api/api_exception.dart';
import 'package:servepos_waiter/core/storage.dart';
import 'package:servepos_waiter/features/auth/session_controller.dart';
import 'package:servepos_waiter/features/order/cart.dart';

import 'support/fakes.dart';

final _dir = Platform.environment['SCREENSHOT_DIR'];

Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final l = FontLoader(name);
    for (final f in files) {
      l.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await l.load();
  }

  await family('Readex Pro', ['ReadexPro_400Regular.ttf', 'ReadexPro_500Medium.ttf', 'ReadexPro_600SemiBold.ttf', 'ReadexPro_700Bold.ttf']);
  await family('Barlow Condensed', ['BarlowCondensed_500Medium.ttf', 'BarlowCondensed_600SemiBold.ttf', 'BarlowCondensed_700Bold.ttf']);
  // Material icons from the Flutter SDK cache.
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/home/claude/tools/flutter';
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final l = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await l.load();
  }
}

final _shot = GlobalKey();

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 400));
  final boundary = _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage(pixelRatio: 3);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final f = File('$_dir/$name.png');
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

AppServices _readyServices({String language = 'en'}) {
  final api = FakeWaiterApi()
    ..ordersJson = [
      orderJson(name: 'WO-2026-00124', status: 'Ready', table: 'T4', minutesAgo: 18, total: 236.5),
      orderJson(name: 'WO-2026-00123', status: 'Pending', table: 'Bed 2', room: 'Pool', minutesAgo: 2, total: 72),
      orderJson(name: 'WO-2026-00121', status: 'In Kitchen', table: 'T2', minutesAgo: 14, total: 104),
      orderJson(name: 'WO-2026-00119', status: 'Accepted', table: null, orderType: 'Takeaway', minutesAgo: 9, total: 58),
      orderJson(name: 'WO-2026-00112', status: 'Served', table: 'T6', minutesAgo: 52, total: 412),
    ]
    ..callsJson = [
      {'name': 'CALL-0091', 'table': 'T7', 'room': 'Terrace', 'created': ago(4), 'status': 'Open', 'accepted_by': null, 'guest_note': 'Can we have the bill please?'},
      {'name': 'CALL-0092', 'table': 'Bed 6', 'room': 'Pool', 'created': ago(1), 'status': 'Open', 'accepted_by': null, 'guest_note': null},
      {'name': 'CALL-0089', 'table': 'T2', 'room': 'Terrace', 'created': ago(6), 'status': 'Accepted', 'accepted_by': 'Ahmed', 'guest_note': 'Extra napkins'},
      {'name': 'CALL-0087', 'table': 'T11', 'room': 'Main hall', 'created': ago(7), 'status': 'Accepted', 'accepted_by': 'Sara', 'guest_note': null},
    ];
  return fakeServices(
    api: api,
    secure: MemoryStore({
      SecureKeys.server: 'https://demo.myapp.qa',
      SecureKeys.token: 'tok',
      SecureKeys.session: jsonEncode(loginJson(profiles: ['Cocktail Bar', 'Beach Grill'])..remove('token')),
    }),
    prefs: MemoryStore({'pos_profile': 'Cocktail Bar', 'language': language, 'biometric': '0', 'last_username': 'ahmed@example.com'}),
  );
}

void _stop(AppServices s) {
  s.floor.setVisible(false);
  s.calls.stopPolling();
  s.outbox.stop();
}

Future<AppServices> _boot(WidgetTester tester, {String language = 'en'}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  final s = _readyServices(language: language);
  await tester.runAsync(() async {
    await _loadFonts();
    await s.init();
    // Let the onReady hooks (menu, floor, orders, calls) finish.
    for (var i = 0; i < 50 && (s.menu.data == null || s.floor.tables.isEmpty || s.calls.calls.isEmpty); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  });
  await tester.pumpWidget(RepaintBoundary(key: _shot, child: WaiterApp(services: s)));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return s;
}

void main() {
  final skip = _dir == null ? 'set SCREENSHOT_DIR to render screenshots' : null;

  testWidgets('01 login', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    final s = fakeServices(
      secure: MemoryStore({SecureKeys.server: 'https://demo.myapp.qa'}),
      prefs: MemoryStore({'last_username': 'ahmed@example.com'}),
    );
    await tester.runAsync(() async {
      await _loadFonts();
      await s.init();
    });
    s.session.loginMessage = 'session_ended';
    await tester.pumpWidget(RepaintBoundary(key: _shot, child: WaiterApp(services: s)));
    await tester.pump(const Duration(milliseconds: 300));
    await _capture(tester, '01_login');
    tester.view.reset();
  }, skip: skip != null);

  testWidgets('02 floor + 03 take order + 04 modifiers + 05 review', (tester) async {
    final s = await _boot(tester);
    expect(s.session.stage, AuthStage.ready);
    // A draft waiting on T5 so the floor shows the badge.
    s.carts.add('table:T5', CartLine.fromItem(s.menu.data!.items.firstWhere((i) => i.itemCode == 'FRIES')));
    await tester.pump(const Duration(milliseconds: 200));
    await _capture(tester, '02_floor');

    // Occupied T2: adds a round to the open order.
    await tester.tap(find.text('T2').first);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final m = s.menu.data!;
    s.carts.add('table:T2', CartLine.fromItem(m.items.firstWhere((i) => i.itemCode == 'MOJ'), qty: 2));
    s.carts.add('table:T2', CartLine.fromItem(m.items.firstWhere((i) => i.itemCode == 'BROWN'), note: 'Warm, with ice cream'));
    await tester.pump(const Duration(milliseconds: 200));
    await _capture(tester, '03_take_order');

    await tester.tap(find.byKey(const Key('item_LATTE')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byKey(const Key('mod_Milk_Oat milk')));
    await tester.tap(find.byKey(const Key('mod_Extras_Vanilla syrup')));
    await tester.pump(const Duration(milliseconds: 200));
    await _capture(tester, '04_modifiers');
    await tester.tap(find.byKey(const Key('mod_add')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.tap(find.byKey(const Key('cart_review')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await _capture(tester, '05_review_sent_and_new');
    _stop(s);
    await tester.pumpWidget(const SizedBox());
    tester.view.reset();
  }, skip: skip != null);

  testWidgets('06 orders offline with waiting outbox', (tester) async {
    final s = await _boot(tester);
    // Takeaway order made while offline: queued, never shown as sent.
    (s.api as FakeWaiterApi).createError = const NetworkException();
    final m = s.menu.data!;
    s.carts.add('takeaway', CartLine.fromItem(m.items.firstWhere((i) => i.itemCode == 'CLUB')));
    s.carts.add('takeaway', CartLine.fromItem(m.items.firstWhere((i) => i.itemCode == 'ESP'), qty: 2));
    await tester.runAsync(() => s.sender.send(target: const CartTarget.takeaway(), posProfile: 'Cocktail Bar', user: 'ahmed@example.com'));
    s.net.report(false);
    await tester.tap(find.text('Orders'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await _capture(tester, '06_orders_offline_outbox');
    _stop(s);
    await tester.pumpWidget(const SizedBox());
    tester.view.reset();
  }, skip: skip != null);

  testWidgets('07 calls + 08 account', (tester) async {
    final s = await _boot(tester);
    await tester.tap(find.text('Calls'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await _capture(tester, '07_calls');
    await tester.tap(find.text('Account'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await _capture(tester, '08_account');
    _stop(s);
    await tester.pumpWidget(const SizedBox());
    tester.view.reset();
  }, skip: skip != null);

  testWidgets('09 floor in Arabic (RTL)', (tester) async {
    final s = await _boot(tester, language: 'ar');
    await tester.tap(find.text('T4').first);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await _capture(tester, '09_take_order_arabic');
    _stop(s);
    await tester.pumpWidget(const SizedBox());
    tester.view.reset();
  }, skip: skip != null);
}
