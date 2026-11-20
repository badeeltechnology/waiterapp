// Scenario harness: a fake ServePOS server at restaurant scale with network
// conditions (latency, timeouts, lost responses, offline), plus helpers to
// boot the real app, count taps and render 1080x2340 screenshots.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servepos_waiter/app/app.dart';
import 'package:servepos_waiter/app/services.dart';
import 'package:servepos_waiter/core/alerts.dart';
import 'package:servepos_waiter/core/api/api_exception.dart';
import 'package:servepos_waiter/core/models/menu.dart';
import 'package:servepos_waiter/core/models/order.dart';
import 'package:servepos_waiter/core/storage.dart';
import 'package:servepos_waiter/features/auth/session_controller.dart';
import 'package:servepos_waiter/features/order/send_controller.dart';

import '../support/fakes.dart';

/// Where screenshots go. Unset: scenarios still run (and assert), no PNGs.
final String? shotDir = Platform.environment['SCREENSHOT_DIR'];

// ---------------------------------------------------------------- data

const sections = ['Section A', 'Section B', 'Section C', 'Section D', 'Section E', 'Section F', 'Sofa', 'Terrace'];

/// 130 tables: A1-A20, B1-B18 + B20A/B20B, C-F 18 each, Sofa S1-S8, Terrace T1-T10.
List<Map<String, dynamic>> bigTablePlan() {
  final out = <Map<String, dynamic>>[];
  void add(String name, String room, int cap) => out.add({'name': name, 'table_name': name, 'room': room, 'capacity': cap});
  for (var i = 1; i <= 20; i++) {
    add('A$i', 'Section A', 4);
  }
  for (var i = 1; i <= 18; i++) {
    add('B$i', 'Section B', 4);
  }
  add('B20A', 'Section B', 2);
  add('B20B', 'Section B', 2);
  for (final s in ['C', 'D', 'E', 'F']) {
    for (var i = 1; i <= 18; i++) {
      add('$s$i', 'Section $s', 4);
    }
  }
  for (var i = 1; i <= 8; i++) {
    add('S$i', 'Sofa', 6);
  }
  for (var i = 1; i <= 10; i++) {
    add('T$i', 'Terrace', 4);
  }
  assert(out.length == 130);
  return out;
}

const _groups = [
  ['Hot Coffee', 'قهوة ساخنة', '#8B5A2B'],
  ['Iced Coffee', 'قهوة مثلجة', '#6F4E37'],
  ['Karak & Tea', 'كرك وشاي', '#C2662B'],
  ['Fresh Juices', 'عصائر طازجة', '#2E9E7A'],
  ['Mocktails', 'موكتيل', '#3F7FD1'],
  ['Breakfast', 'فطور', '#D9A21B'],
  ['Sandwiches', 'سندويشات', '#A0522D'],
  ['Mains', 'أطباق رئيسية', '#B23A48'],
  ['Salads', 'سلطات', '#4E9A2F'],
  ['Shisha', 'شيشة', '#7C5CBF'],
  ['Desserts', 'حلويات', '#C25B8C'],
  ['Kids', 'أطفال', '#0E6E86'],
];

const _en = [
  'Grilled Halloumi & Za\'atar Flatbread with Pomegranate Molasses',
  'Spanish Latte with Saffron Cream and Cardamom Foam',
  'Chicken Shawarma Wrap with Garlic Toum and Pickles',
  'Slow-Cooked Lamb Ouzi on Spiced Rice with Roasted Nuts',
  'Karak Chai with Evaporated Milk and Ginger',
  'Mango Passion Fruit Mojito with Fresh Mint',
  'Classic Club Sandwich with Fries and Coleslaw',
  'Truffle Mushroom Risotto with Parmesan Shavings',
  'Fattoush Salad with Sumac Pita Crisps',
  'Double Apple Shisha (Premium Tobacco)',
  'Pistachio Kunafa with Clotted Cream and Rose Syrup',
  'Kids Chicken Nuggets with Mini Fries and Juice',
];

const _ar = [
  'خبز مسطح بالحلوم المشوي والزعتر مع دبس الرمان',
  'سبانش لاتيه بكريمة الزعفران ورغوة الهيل',
  'لفافة شاورما دجاج مع ثومية ومخللات',
  'أوزي لحم مطهو ببطء على أرز متبل مع مكسرات محمصة',
  'شاي كرك بالحليب المبخر والزنجبيل',
  'موهيتو مانجو وباشن فروت بالنعناع الطازج',
  'كلوب ساندويتش كلاسيك مع بطاطس وسلطة ملفوف',
  'ريزوتو الفطر بالكمأة مع شرائح البارميزان',
  'سلطة فتوش مع رقائق الخبز بالسماق',
  'شيشة تفاحتين (معسل فاخر)',
  'كنافة بالفستق مع القشطة وشراب الورد',
  'ناجتس دجاج للأطفال مع بطاطس صغيرة وعصير',
];

/// ~300 items in 12 groups with long EN/AR names and required modifiers.
MenuData bigMenu() {
  final items = <Map<String, dynamic>>[];
  var sort = 0;
  for (var g = 0; g < _groups.length; g++) {
    for (var i = 0; i < 25; i++) {
      final code = 'I${g.toString().padLeft(2, '0')}${i.toString().padLeft(2, '0')}';
      final suffix = i == 0 ? '' : ' No. ${i + 1}';
      final mods = switch (g) {
        0 || 1 => ['Milk', 'Size', 'Extras'],
        2 => ['Sugar'],
        6 || 7 => ['Cook', 'Side'],
        9 => ['Flavour'],
        _ => <String>[],
      };
      items.add({
        'item_code': code,
        'item_name': '${_en[g]}$suffix',
        'item_name_ar': '${_ar[g]}${i == 0 ? '' : ' ${i + 1}'}',
        'item_group': _groups[g][0],
        'rate': 18.0 + (g * 7 + i * 3) % 90,
        'modifier_groups': mods,
        'is_available': !(g == 10 && i == 3),
        'sort': sort++,
      });
    }
  }
  // A few short, findable names used by the scenarios.
  items.addAll([
    {
      'item_code': 'KARAK',
      'item_name': 'Karak',
      'item_name_ar': 'كرك',
      'item_group': 'Karak & Tea',
      'rate': 8.0,
      'modifier_groups': ['Sugar'],
      'sort': sort++,
    },
    {
      'item_code': 'LATTE',
      'item_name': 'Iced Spanish Latte',
      'item_name_ar': 'سبانش لاتيه مثلج',
      'item_group': 'Iced Coffee',
      'rate': 28.0,
      'modifier_groups': ['Milk', 'Size', 'Extras'],
      'sort': sort++,
    },
    {
      'item_code': 'BURGER',
      'item_name': 'Wagyu Beef Burger with Caramelised Onions and Smoked Cheddar',
      'item_name_ar': 'برغر لحم واغيو مع بصل مكرمل وشيدر مدخن',
      'item_group': 'Mains',
      'rate': 68.0,
      'modifier_groups': ['Cook', 'Side'],
      'sort': sort++,
    },
    {
      'item_code': 'WATER',
      'item_name': 'Still Water 500 ml',
      'item_name_ar': 'مياه 500 مل',
      'item_group': 'Fresh Juices',
      'rate': 6.0,
      'sort': sort++,
    },
  ]);
  Map<String, dynamic> grp(String name, bool req, String type, int max, List<List<Object>> m) => {
    'name': name,
    'selection_type': type,
    'is_required': req,
    'max_selections': max,
    'modifiers': [
      for (final x in m) {'name': x[0], 'price': x[1], if (x.length > 2) 'is_default': x[2]},
    ],
  };
  return MenuData.fromJson({
    'version': 'big-1',
    'currency': 'QAR',
    'currency_precision': 2,
    'settings': {'allow_cancel_pending': true},
    'item_groups': [
      for (var g = 0; g < _groups.length; g++) {'name': _groups[g][0], 'name_ar': _groups[g][1], 'sort': g, 'color': _groups[g][2]},
    ],
    'items': items,
    'modifier_groups': [
      grp('Milk', true, 'Single', 1, [
        ['Full cream', 0],
        ['Oat milk', 3.0],
        ['Almond milk', 3.0],
        ['Lactose free', 2.0],
      ]),
      grp('Size', true, 'Single', 1, [
        ['Regular', 0],
        ['Large', 6.0],
      ]),
      grp('Extras', false, 'Multiple', 2, [
        ['Extra shot', 4.0],
        ['Vanilla syrup', 2.0],
        ['Caramel syrup', 2.0],
        ['Less ice', 0],
      ]),
      grp('Sugar', true, 'Single', 1, [
        ['No sugar', 0],
        ['Less sugar', 0],
        ['Normal', 0],
        ['Extra sweet', 0],
      ]),
      grp('Cook', true, 'Single', 1, [
        ['Medium rare', 0],
        ['Medium', 0],
        ['Well done', 0],
      ]),
      grp('Side', true, 'Single', 1, [
        ['Fries', 0],
        ['Salad', 0],
        ['Sweet potato fries', 5.0],
      ]),
      grp('Flavour', true, 'Single', 1, [
        ['Double apple', 0],
        ['Grape mint', 0],
        ['Lemon mint', 0],
      ]),
    ],
    'rooms': [
      for (final s in sections) {'name': s, 'room_name': s},
    ],
    'tables': bigTablePlan(),
  });
}

// ---------------------------------------------------------------- server

/// Fake server with real idempotency (same client_request_id → same order)
/// and scriptable network conditions.
class ScenarioApi extends FakeWaiterApi {
  ScenarioApi() {
    menu = bigMenu();
    tablesJson = [];
  }

  /// Time the server takes to answer every order call.
  Duration latency = Duration.zero;

  /// Client-side timeout (ApiClient uses 15 s).
  Duration clientTimeout = const Duration(seconds: 15);

  /// Device has no connection: calls fail fast with NetworkException.
  bool offline = false;

  /// The next N order calls are processed by the server but the answer is lost
  /// (client sees a timeout).
  int loseResponses = 0;

  /// The next N order calls fail with HTTP 502 BEFORE reaching the app server.
  int gatewayErrors = 0;

  /// Reported like ApiClient.onReachability.
  void Function(bool reachable)? reachability;

  /// Every order HTTP request that reached the server, in order.
  final requests = <({String method, String id, String? order, int items, DateTime at})>[];

  /// Distinct server-side orders and rounds (after idempotency).
  final ordersByName = <String, Map<String, dynamic>>{};
  final _byRequestId = <String, String>{}; // client_request_id -> order name
  int _next = 300;

  int get orderCount => ordersByName.length;
  int roundsOf(String name) => (ordersByName[name]?['rounds'] as int?) ?? 0;
  int get createRequests => requests.where((r) => r.method == 'create').length;
  int get addRequests => requests.where((r) => r.method == 'add_items').length;
  Set<String> get distinctRequestIds => {for (final r in requests) r.id};

  /// Changes a server order's status (the till accepted it, kitchen marked ready).
  void setStatus(String name, String status) {
    ordersByName[name]!['status'] = status;
  }

  Future<T> _net<T>(T Function() server, {required String method, required Map<String, dynamic> payload}) async {
    calls.add(method);
    if (offline) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      reachability?.call(false);
      throw const NetworkException();
    }
    if (gatewayErrors > 0) {
      gatewayErrors--;
      await Future<void>.delayed(latency);
      reachability?.call(true);
      throw const ServerException('The server had a problem (HTTP 502). Try again.', statusCode: 502);
    }
    final lose = loseResponses > 0;
    if (lose) loseResponses--;
    if (latency >= clientTimeout || lose) {
      // The server works on it; the phone gives up.
      final wait = latency >= clientTimeout ? clientTimeout : latency;
      await Future<void>.delayed(wait);
      server();
      reachability?.call(false);
      throw const TimeoutApiException();
    }
    await Future<void>.delayed(latency);
    final r = server();
    reachability?.call(true);
    return r;
  }

  Map<String, dynamic> _items(List items, int round) => {
    'lines': [
      for (final i in items)
        {
          'item_code': i['item_code'],
          'item_name': menu!.items.firstWhere((m) => m.itemCode == i['item_code']).itemName,
          'qty': i['qty'],
          'rate': menu!.items.firstWhere((m) => m.itemCode == i['item_code']).rate,
          'modifiers': i['modifiers'],
          'modifier_total': 0,
          'amount': menu!.items.firstWhere((m) => m.itemCode == i['item_code']).rate * (i['qty'] as num),
          'special_instructions': i['special_instructions'],
          'round': round,
          'added_by': 'Ahmed',
        },
    ],
  };

  Map<String, dynamic> _orderJson(String name) {
    final o = ordersByName[name]!;
    final lines = [for (final l in o['lines'] as List) l as Map<String, dynamic>];
    return {
      'name': name,
      'status': o['status'],
      'pos_profile': 'Cocktail Bar',
      'table': o['table'],
      'room': o['room'],
      'order_type': o['table'] == null ? 'Takeaway' : 'Dine In',
      'guests': o['guests'] ?? 0,
      'waiter': 'Ahmed',
      'created': o['created'],
      'modified': o['created'],
      'notes': '',
      'total': lines.fold<double>(0, (a, l) => a + (l['amount'] as num)),
      'currency': 'QAR',
      'items': lines,
    };
  }

  @override
  Future<Order> createOrder(Map<String, dynamic> payload) => _net(
    () {
      if (createError != null) throw createError!;
      final id = payload['client_request_id'] as String;
      requests.add((method: 'create', id: id, order: null, items: (payload['items'] as List).length, at: DateTime.now()));
      final existing = _byRequestId[id];
      if (existing != null) return Order.fromJson(_orderJson(existing));
      final name = 'WO-2026-00${_next++}';
      _byRequestId[id] = name;
      ordersByName[name] = {
        'status': 'Pending',
        'table': payload['table'],
        'room': payload['room'],
        'guests': payload['guests'],
        'created': ago(0),
        'rounds': 1,
        'lines': _items(payload['items'] as List, 1)['lines'],
      };
      payloads.add(payload);
      createdIds.add(id);
      return Order.fromJson(_orderJson(name));
    },
    method: 'create',
    payload: payload,
  );

  @override
  Future<Order> addItems(Map<String, dynamic> payload) => _net(
    () {
      final id = payload['client_request_id'] as String;
      final name = payload['order'] as String?;
      requests.add((method: 'add_items', id: id, order: name, items: (payload['items'] as List).length, at: DateTime.now()));
      final existing = _byRequestId[id];
      if (existing != null) return Order.fromJson(_orderJson(existing));
      if (name == null || !ordersByName.containsKey(name)) {
        throw const ServerException('Order not found', statusCode: 404);
      }
      _byRequestId[id] = name;
      final o = ordersByName[name]!;
      final round = (o['rounds'] as int) + 1;
      o['rounds'] = round;
      (o['lines'] as List).addAll(_items(payload['items'] as List, round)['lines'] as List);
      payloads.add(payload);
      return Order.fromJson(_orderJson(name));
    },
    method: 'add_items',
    payload: payload,
  );

  @override
  Future<List<TableLive>> tables(String posProfile) async {
    calls.add('tables');
    if (offline) {
      reachability?.call(false);
      throw const NetworkException();
    }
    final open = <String, String>{};
    for (final e in ordersByName.entries) {
      final t = e.value['table'];
      if (t != null && e.value['status'] != 'Paid') open[t as String] = e.key;
    }
    return [
      for (final t in bigTablePlan())
        TableLive.fromJson({
          ...t,
          'status': open.containsKey(t['name']) ? 'Occupied' : 'Available',
          if (open.containsKey(t['name']))
            'order': {
              'order': open[t['name']],
              'waiter': 'Ahmed',
              'guests': ordersByName[open[t['name']]]!['guests'] ?? 0,
              'since': ordersByName[open[t['name']]]!['created'],
              'total': _orderJson(open[t['name']]!)['total'],
              'items_count': (ordersByName[open[t['name']]]!['lines'] as List).length,
              'status': ordersByName[open[t['name']]]!['status'],
            },
        }),
    ];
  }

  @override
  Future<List<Order>> myOrders(String posProfile, {required bool all, int days = 1}) async {
    calls.add('orders');
    if (offline) throw const NetworkException();
    final names = ordersByName.keys.toList().reversed;
    return [for (final n in names) Order.fromJson(_orderJson(n))];
  }

  @override
  Future<Order> order(String name) async {
    calls.add('order $name');
    if (offline) throw const NetworkException();
    if (!ordersByName.containsKey(name)) throw const ServerException('Not found', statusCode: 404);
    return Order.fromJson(_orderJson(name));
  }
}

// ---------------------------------------------------------------- app

/// Records alerts so scenarios can check what rang.
class RecordingAlerts extends NoopAlerts {}

class Harness {
  Harness(this.tester, this.services, this.api);
  final WidgetTester tester;
  final AppServices services;
  final ScenarioApi api;
  int taps = 0;
  final log = <String>[];

  RecordingAlerts get alerts => services.alerts as RecordingAlerts;
  RecordingFeedback get feedback => services.sending.feedback as RecordingFeedback;

  Future<void> tap(Finder f, {String? note}) async {
    taps++;
    if (note != null) log.add('tap ${taps.toString().padLeft(2)}: $note');
    await tester.tap(f, warnIfMissed: false);
    await tester.pump();
  }

  Future<void> type(Finder f, String text) async {
    taps += text.length; // one tap per key
    log.add('type "$text" (${text.length} keys)');
    await tester.enterText(f, text);
    await tester.pump();
  }

  /// Advances fake time in small steps so animations and futures settle.
  Future<void> wait(Duration d) async {
    var left = d;
    const step = Duration(milliseconds: 100);
    while (left > Duration.zero) {
      final s = left < step ? left : step;
      await tester.pump(s);
      left -= s;
    }
  }

  /// Pumps until [f] shows up (or [max] passes). Returns whether it did.
  Future<bool> waitFor(Finder f, {Duration max = const Duration(seconds: 20)}) async {
    var t = Duration.zero;
    while (t < max) {
      if (f.evaluate().isNotEmpty) return true;
      await tester.pump(const Duration(milliseconds: 250));
      t += const Duration(milliseconds: 250);
    }
    return f.evaluate().isNotEmpty;
  }

  Future<void> shot(String name) async {
    if (shotDir == null) return;
    await tester.pump(const Duration(milliseconds: 50));
    final boundary = shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final ui.Image image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final f = File('$shotDir/$name.png');
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    log.add('screenshot $name.png');
  }

  void stop() {
    services.orders.stopPolling();
    services.floor.setVisible(false);
    services.calls.stopPolling();
    services.outbox.stop();
  }

  Future<void> dispose() async {
    stop();
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    tester.view.reset();
    debugDisableShadows = true;
  }
}

final shotKey = GlobalKey();
bool _fontsLoaded = false;

Future<void> loadFonts() async {
  if (_fontsLoaded) return;
  Future<void> family(String name, List<String> files) async {
    final l = FontLoader(name);
    for (final f in files) {
      l.addFont(rootBundle.load('assets/fonts/$f'));
    }
    await l.load();
  }

  await family('Readex Pro', ['ReadexPro_400Regular.ttf', 'ReadexPro_500Medium.ttf', 'ReadexPro_600SemiBold.ttf', 'ReadexPro_700Bold.ttf']);
  await family('Barlow Condensed', ['BarlowCondensed_500Medium.ttf', 'BarlowCondensed_600SemiBold.ttf', 'BarlowCondensed_700Bold.ttf']);
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/home/claude/tools/flutter';
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final l = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await l.load();
  }
  _fontsLoaded = true;
}

/// Boots the signed-in app on a 1080x2340 phone with the big restaurant.
Future<Harness> boot(WidgetTester tester, {String language = 'en', ScenarioApi? api}) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  // flutter_test paints elevation as a thick black outline unless real shadows are on.
  debugDisableShadows = false;
  final a = api ?? ScenarioApi();
  final s = fakeServices(
    api: a,
    alerts: RecordingAlerts(),
    secure: MemoryStore({
      SecureKeys.server: 'https://erp.example.com',
      SecureKeys.token: 'tok',
      SecureKeys.session: jsonEncode(loginJson()..remove('token')),
    }),
    prefs: MemoryStore({'pos_profile': 'Cocktail Bar', 'language': language, 'biometric': '0', 'last_username': 'ahmed@example.com'}),
  );
  a.reachability = s.net.report;
  await tester.runAsync(() async {
    await loadFonts(); // real fonts always: Ahem would overflow at real-phone widths
    await s.init();
    for (var i = 0; i < 100 && (s.menu.data == null || s.floor.tables.isEmpty); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  });
  // Timers are driven by the scenarios, not by wall clock.
  s.outbox.stop();
  s.calls.stopPolling();
  s.orders.stopPolling();
  await tester.pumpWidget(
    RepaintBoundary(
      key: shotKey,
      child: WaiterApp(services: s),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  s.floor.setVisible(false);
  return Harness(tester, s, a);
}

/// Writes a scenario's tap log and metrics next to the screenshots.
void report(String scenario, Harness h, Map<String, Object?> metrics) {
  final dir = shotDir;
  final line = jsonEncode({'scenario': scenario, 'taps': h.taps, ...metrics, 'log': h.log});
  // ignore: avoid_print
  print('SCENARIO $line');
  if (dir == null) return;
  final f = File('$dir/scenarios.jsonl');
  f.parent.createSync(recursive: true);
  f.writeAsStringSync('$line\n', mode: FileMode.append);
}
