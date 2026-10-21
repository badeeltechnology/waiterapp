import 'package:servepos_waiter/app/services.dart';
import 'package:servepos_waiter/core/alerts.dart';
import 'package:servepos_waiter/core/api/api_exception.dart';
import 'package:servepos_waiter/core/api/waiter_api.dart';
import 'package:servepos_waiter/core/models/menu.dart';
import 'package:servepos_waiter/core/models/order.dart';
import 'package:servepos_waiter/core/models/session.dart';
import 'package:servepos_waiter/core/platform.dart';
import 'package:servepos_waiter/core/push.dart';
import 'package:servepos_waiter/core/storage.dart';

class FakeBiometric implements BiometricGate {
  FakeBiometric({this.available = true, this.succeed = true});
  bool available;
  bool succeed;
  int prompts = 0;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<bool> authenticate(String reason) async {
    prompts++;
    return succeed;
  }
}

class FakeDeviceFacts extends DeviceFactsProvider {
  FakeDeviceFacts(super.secure);
  @override
  Future<DeviceFacts> facts() async =>
      DeviceFacts(deviceId: await deviceId(), deviceName: 'Test Phone', platform: 'Android 15', appVersion: '2.0.0+3');
}

Map<String, dynamic> loginJson({List<String> profiles = const ['Cocktail Bar'], String token = 'tok-1'}) => {
      'token': token,
      'expires_on': '2026-11-20 10:00:00',
      'user': {'user': 'ahmed@example.com', 'full_name': 'Ahmed Khalil', 'waiter': 'Ahmed', 'image': null},
      'pos_profiles': [
        for (final p in profiles) {'name': p, 'restaurant_name': p.toUpperCase(), 'branch': 'Beach Club', 'currency': 'QAR'},
      ],
      'default_pos_profile': profiles.first,
      'server': {'site': 'demo.myapp.qa', 'servepos_version': '2.0.0', 'time': ago(0)},
    };

MenuData sampleMenu() => MenuData.fromJson({
      'version': 'v1',
      'currency': 'QAR',
      'currency_precision': 2,
      'settings': {'allow_cancel_pending': true},
      'item_groups': [
        {'name': 'Coffee', 'name_ar': 'قهوة', 'sort': 1, 'color': '#8B5A2B'},
        {'name': 'Mocktails', 'name_ar': 'موكتيل', 'sort': 2, 'color': '#2E9E7A'},
        {'name': 'Food', 'name_ar': 'طعام', 'sort': 3, 'color': '#A0522D'},
        {'name': 'Desserts', 'name_ar': 'حلويات', 'sort': 4, 'color': '#C25B8C'},
      ],
      'items': [
        {'item_code': 'LATTE', 'item_name': 'Iced Latte', 'item_name_ar': 'لاتيه مثلج', 'item_group': 'Coffee', 'rate': 28.0, 'modifier_groups': ['Milk', 'Extras'], 'sort': 1},
        {'item_code': 'ESP', 'item_name': 'Espresso', 'item_name_ar': 'إسبريسو', 'item_group': 'Coffee', 'rate': 16.0, 'sort': 2},
        {'item_code': 'CAP', 'item_name': 'Cappuccino', 'item_name_ar': 'كابتشينو', 'item_group': 'Coffee', 'rate': 24.0, 'modifier_groups': ['Milk'], 'sort': 3},
        {'item_code': 'SPAN', 'item_name': 'Spanish Latte', 'item_name_ar': 'سبانش لاتيه', 'item_group': 'Coffee', 'rate': 30.0, 'sort': 4},
        {'item_code': 'MOJ', 'item_name': 'Blue Lagoon Mojito', 'item_name_ar': 'موهيتو بلو لاغون', 'item_group': 'Mocktails', 'rate': 30.0, 'sort': 5},
        {'item_code': 'MANGO', 'item_name': 'Mango Tango 16 oz', 'item_name_ar': 'مانجو تانجو', 'item_group': 'Mocktails', 'rate': 34.0, 'sort': 6},
        {'item_code': 'CLUB', 'item_name': 'Club Sandwich', 'item_name_ar': 'كلوب ساندويتش', 'item_group': 'Food', 'rate': 42.0, 'sort': 7},
        {'item_code': 'FRIES', 'item_name': 'Fries', 'item_name_ar': 'بطاطس مقلية', 'item_group': 'Food', 'rate': 18.0, 'sort': 8},
        {'item_code': 'BROWN', 'item_name': 'Brownies', 'item_name_ar': 'براونيز', 'item_group': 'Desserts', 'rate': 24.0, 'sort': 9},
        {'item_code': 'CAKE', 'item_name': 'Pistachio Cake', 'item_name_ar': 'كيك الفستق', 'item_group': 'Desserts', 'rate': 32.0, 'is_available': false, 'sort': 10},
      ],
      'modifier_groups': [
        {
          'name': 'Milk',
          'selection_type': 'Single',
          'is_required': true,
          'max_selections': 1,
          'modifiers': [
            {'name': 'Full cream', 'price': 0, 'is_default': true},
            {'name': 'Oat milk', 'price': 3.0},
            {'name': 'Almond milk', 'price': 3.0},
          ],
        },
        {
          'name': 'Extras',
          'selection_type': 'Multiple',
          'is_required': false,
          'max_selections': 2,
          'modifiers': [
            {'name': 'Extra shot', 'price': 4.0},
            {'name': 'Vanilla syrup', 'price': 2.0},
            {'name': 'Caramel syrup', 'price': 2.0},
            {'name': 'Less ice', 'price': 0},
          ],
        },
      ],
      'rooms': [
        {'name': 'Terrace', 'room_name': 'Terrace'},
        {'name': 'Pool', 'room_name': 'Pool'},
        {'name': 'Main hall', 'room_name': 'Main hall'},
      ],
      'tables': [
        for (var i = 1; i <= 6; i++) {'name': 'T$i', 'table_name': 'T$i', 'room': 'Terrace', 'capacity': 4},
        for (var i = 1; i <= 4; i++) {'name': 'Bed $i', 'table_name': 'Bed $i', 'room': 'Pool', 'capacity': 2},
        for (var i = 10; i <= 13; i++) {'name': 'T$i', 'table_name': 'T$i', 'room': 'Main hall', 'capacity': 6},
      ],
    });

String ago(int minutes) {
  final t = DateTime.now().subtract(Duration(minutes: minutes));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

Map<String, dynamic> orderJson({
  String name = 'WO-2026-00119',
  String status = 'Pending',
  String? table = 'T2',
  String room = 'Terrace',
  String waiter = 'Ahmed',
  int minutesAgo = 4,
  double total = 104,
  List<Map<String, dynamic>>? items,
  String orderType = 'Dine In',
}) =>
    {
      'name': name,
      'status': status,
      'pos_profile': 'Cocktail Bar',
      'table': table,
      'room': room,
      'order_type': orderType,
      'guests': 3,
      'waiter': waiter,
      'created': ago(minutesAgo),
      'modified': ago(minutesAgo),
      'notes': '',
      'total': total,
      'currency': 'QAR',
      'items': items ??
          [
            {'item_code': 'LATTE', 'item_name': 'Iced Latte', 'qty': 2, 'rate': 28.0, 'modifiers': [{'group': 'Milk', 'name': 'Oat milk', 'price': 3.0}], 'modifier_total': 3.0, 'amount': 62.0, 'special_instructions': '', 'round': 1, 'added_by': waiter},
            {'item_code': 'CLUB', 'item_name': 'Club Sandwich', 'qty': 1, 'rate': 42.0, 'modifiers': [], 'modifier_total': 0, 'amount': 42.0, 'special_instructions': 'no mayo', 'round': 1, 'added_by': waiter},
          ],
    };

List<Map<String, dynamic>> sampleTables() => [
      {'name': 'T1', 'table_name': 'T1', 'room': 'Terrace', 'capacity': 4, 'status': 'Available'},
      {
        'name': 'T2', 'table_name': 'T2', 'room': 'Terrace', 'capacity': 4, 'status': 'Occupied',
        'order': {'order': 'WO-2026-00119', 'waiter': 'Ahmed', 'guests': 3, 'since': ago(14), 'total': 104.0, 'items_count': 3, 'status': 'In Kitchen'},
      },
      {'name': 'T3', 'table_name': 'T3', 'room': 'Terrace', 'capacity': 4, 'status': 'Reserved'},
      {
        'name': 'T4', 'table_name': 'T4', 'room': 'Terrace', 'capacity': 4, 'status': 'Occupied',
        'order': {'order': 'WO-2026-00121', 'waiter': 'Sara', 'guests': 2, 'since': ago(38), 'total': 236.5, 'items_count': 7, 'status': 'Ready'},
      },
      {'name': 'T5', 'table_name': 'T5', 'room': 'Terrace', 'capacity': 4, 'status': 'Available'},
      {
        'name': 'T6', 'table_name': 'T6', 'room': 'Terrace', 'capacity': 6, 'status': 'Occupied',
        'order': {'order': 'WO-2026-00117', 'waiter': 'Omar', 'guests': 5, 'since': ago(52), 'total': 412.0, 'items_count': 12, 'status': 'Served'},
      },
      {'name': 'Bed 1', 'table_name': 'Bed 1', 'room': 'Pool', 'capacity': 2, 'status': 'Available'},
      {
        'name': 'Bed 2', 'table_name': 'Bed 2', 'room': 'Pool', 'capacity': 2, 'status': 'Occupied',
        'order': {'order': 'WO-2026-00122', 'waiter': 'Fatima', 'guests': 2, 'since': ago(6), 'total': 72.0, 'items_count': 3, 'status': 'Pending'},
      },
    ];

/// Scriptable fake of the server contract.
class FakeWaiterApi implements WaiterApi {
  @override
  String? baseUrl;
  @override
  String? token;
  void Function()? _expired;
  @override
  set onSessionExpired(void Function()? cb) => _expired = cb;

  final calls = <String>[];
  bool pingOk = true;
  Map<String, dynamic> loginResponse = loginJson();
  ApiException? loginError;
  ApiException? meError;
  Map<String, dynamic>? meResponse;
  MenuData? menu = sampleMenu();
  List<Map<String, dynamic>> tablesJson = sampleTables();
  List<Map<String, dynamic>> ordersJson = [];
  List<Map<String, dynamic>> callsJson = [];
  ApiException? createError;
  final createdIds = <String>[];
  final List<Map<String, dynamic>> payloads = [];
  int _seq = 200;

  /// Simulates the server answering 401 on the next authed call.
  bool expireNext = false;

  Future<T> _authed<T>(String name, T Function() body) async {
    calls.add(name);
    if (expireNext) {
      expireNext = false;
      _expired?.call();
      throw const SessionExpiredException();
    }
    return body();
  }

  @override
  Future<bool> ping(String baseUrl) async {
    calls.add('ping $baseUrl');
    return pingOk;
  }

  @override
  Future<LoginResult> login({required String usr, required String pwd, required DeviceFacts device}) async {
    calls.add('login $usr ${device.deviceId.isNotEmpty}');
    if (loginError != null) throw loginError!;
    if (pwd != 'secret') throw const LoginRejectedException('Incorrect password');
    return LoginResult(loginResponse['token'] as String, SessionInfo.fromJson(loginResponse));
  }

  @override
  Future<SessionInfo> me() => _authed('me', () {
        if (meError != null) throw meError!;
        return SessionInfo.fromJson(meResponse ?? (Map.of(loginResponse)..remove('token')));
      });

  @override
  Future<void> logout({String? tokenOverride}) async => calls.add('logout ${tokenOverride ?? token}');

  @override
  Future<List<DeviceSession>> sessions() => _authed('sessions', () => [
        const DeviceSession(name: 'DS-1', deviceName: 'Samsung SM-A546E', platform: 'Android 15', lastSeen: '2026-10-21 08:00:00', current: true),
        const DeviceSession(name: 'DS-2', deviceName: 'Xiaomi Redmi Note 12', platform: 'Android 14', lastSeen: '2026-10-18 22:10:00'),
      ]);

  @override
  Future<void> revokeSession(String name) => _authed('revoke $name', () {});

  @override
  Future<void> registerPush(String fcmToken, String platform) => _authed('push', () {});

  @override
  Future<BootstrapResult> bootstrap(String posProfile, {String? version}) => _authed('bootstrap', () {
        if (menu == null) throw const NetworkException();
        if (version == menu!.version) return const BootstrapResult.unchanged();
        return BootstrapResult.fresh(menu!);
      });

  @override
  Future<List<TableLive>> tables(String posProfile) => _authed('tables', () => tablesJson.map(TableLive.fromJson).toList());

  Order _orderFrom(Map<String, dynamic> payload) {
    final id = payload['client_request_id'] as String;
    createdIds.add(id);
    payloads.add(payload);
    return Order.fromJson(orderJson(name: 'WO-2026-00${_seq++}', table: payload['table'] as String?));
  }

  @override
  Future<Order> createOrder(Map<String, dynamic> payload) => _authed('create', () {
        if (createError != null) throw createError!;
        return _orderFrom(payload);
      });

  @override
  Future<Order> addItems(Map<String, dynamic> payload) => _authed('add_items', () {
        if (createError != null) throw createError!;
        return _orderFrom(payload);
      });

  @override
  Future<List<Order>> myOrders(String posProfile, {required bool all, int days = 1}) =>
      _authed('orders', () => ordersJson.map(Order.fromJson).toList());

  @override
  Future<Order> order(String name) => _authed('order $name', () {
        final j = ordersJson.where((o) => o['name'] == name).firstOrNull ?? orderJson(name: name);
        return Order.fromJson(j);
      });

  @override
  Future<void> cancelOrder(String name, String reason) => _authed('cancel $name', () {});

  @override
  Future<List<GuestCall>> activeCalls(String posProfile) => _authed('calls', () => callsJson.map(GuestCall.fromJson).toList());

  CallAcceptResult acceptResult = const CallAcceptResult(ok: true);
  @override
  Future<CallAcceptResult> acceptCall(String name) => _authed('accept $name', () => acceptResult);

  @override
  Future<void> attendCall(String name) => _authed('attended $name', () {});
}

AppServices fakeServices({
  FakeWaiterApi? api,
  MemoryStore? secure,
  MemoryStore? prefs,
  FakeBiometric? biometric,
  Alerts? alerts,
}) {
  final s = secure ?? MemoryStore();
  return AppServices(
    api: api ?? FakeWaiterApi(),
    secure: s,
    prefs: prefs ?? MemoryStore(),
    json: MemoryJsonStore(),
    biometric: biometric ?? FakeBiometric(),
    alerts: alerts ?? NoopAlerts(),
    push: NoopPush(),
    net: NetStatus(listenToDevice: false),
    facts: FakeDeviceFacts(s),
    allowInsecureLocal: false,
    httpsOnly: false,
  );
}
