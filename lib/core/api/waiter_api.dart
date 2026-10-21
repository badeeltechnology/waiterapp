import '../models/menu.dart';
import '../models/order.dart';
import '../models/session.dart';
import 'api_client.dart';
import 'api_exception.dart';

/// Device facts sent with login.
class DeviceFacts {
  const DeviceFacts({required this.deviceId, required this.deviceName, required this.platform, required this.appVersion});
  final String deviceId;
  final String deviceName;
  final String platform;
  final String appVersion;
}

/// Result of `bootstrap`: either fresh data or "unchanged".
class BootstrapResult {
  const BootstrapResult.fresh(MenuData this.data) : unchanged = false;
  const BootstrapResult.unchanged()
      : data = null,
        unchanged = true;
  final MenuData? data;
  final bool unchanged;
}

class CallAcceptResult {
  const CallAcceptResult({required this.ok, this.acceptedBy});
  final bool ok;
  final String? acceptedBy;
}

/// Every server call the app makes, exactly as WAITER_API_V2.md defines them.
abstract class WaiterApi {
  String? get baseUrl;
  set baseUrl(String? v);
  String? get token;
  set token(String? v);
  set onSessionExpired(void Function()? cb);

  Future<bool> ping(String baseUrl);
  Future<LoginResult> login({required String usr, required String pwd, required DeviceFacts device});
  Future<SessionInfo> me();
  Future<void> logout({String? tokenOverride});
  Future<List<DeviceSession>> sessions();
  Future<void> revokeSession(String name);
  Future<void> registerPush(String fcmToken, String platform);

  Future<BootstrapResult> bootstrap(String posProfile, {String? version});
  Future<List<TableLive>> tables(String posProfile);
  Future<Order> createOrder(Map<String, dynamic> payload);
  Future<Order> addItems(Map<String, dynamic> payload);
  Future<List<Order>> myOrders(String posProfile, {required bool all, int days = 1});
  Future<Order> order(String name);
  Future<void> cancelOrder(String name, String reason);

  Future<List<GuestCall>> activeCalls(String posProfile);
  Future<CallAcceptResult> acceptCall(String name);
  Future<void> attendCall(String name);
}

const _m = 'servepos.api.mobile';

class HttpWaiterApi implements WaiterApi {
  HttpWaiterApi(this.client);
  final ApiClient client;

  @override
  String? get baseUrl => client.baseUrl;
  @override
  set baseUrl(String? v) => client.baseUrl = v;
  @override
  String? get token => client.token;
  @override
  set token(String? v) => client.token = v;
  @override
  set onSessionExpired(void Function()? cb) => client.onSessionExpired = cb;

  Map<String, dynamic> _map(Object? v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    throw const BadResponseException();
  }

  List<Map<String, dynamic>> _list(Object? v) {
    if (v is Map) {
      // Tolerate {"tables": [...]}, {"orders": [...]}, {"data": [...]}.
      final inner = v.values.firstWhere((e) => e is List, orElse: () => null);
      if (inner is List) v = inner;
    }
    if (v is! List) throw const BadResponseException();
    return [for (final e in v) if (e is Map) Map<String, dynamic>.from(e)];
  }

  @override
  Future<bool> ping(String baseUrl) => client.ping(baseUrl);

  @override
  Future<LoginResult> login({required String usr, required String pwd, required DeviceFacts device}) async {
    final r = _map(await client.post('$_m.auth.login', isLogin: true, body: {
      'usr': usr,
      'pwd': pwd,
      'device_id': device.deviceId,
      'device_name': device.deviceName,
      'platform': device.platform,
      'app_version': device.appVersion,
    }));
    final token = r['token']?.toString();
    if (token == null || token.isEmpty) throw const BadResponseException();
    return LoginResult(token, SessionInfo.fromJson(r));
  }

  @override
  Future<SessionInfo> me() async => SessionInfo.fromJson(_map(await client.get('$_m.auth.me')));

  @override
  Future<void> logout({String? tokenOverride}) => client.post('$_m.auth.logout', overrideToken: tokenOverride);

  @override
  Future<List<DeviceSession>> sessions() async =>
      _list(await client.get('$_m.auth.sessions')).map(DeviceSession.fromJson).toList();

  @override
  Future<void> revokeSession(String name) => client.post('$_m.auth.revoke_session', body: {'name': name});

  @override
  Future<void> registerPush(String fcmToken, String platform) =>
      client.post('$_m.push.register', body: {'token': fcmToken, 'platform': platform});

  @override
  Future<BootstrapResult> bootstrap(String posProfile, {String? version}) async {
    final r = _map(await client.get('$_m.waiter.bootstrap', query: {'pos_profile': posProfile, 'version': version}));
    if (r['unchanged'] == true || r['unchanged'] == 1) return const BootstrapResult.unchanged();
    return BootstrapResult.fresh(MenuData.fromJson(r));
  }

  @override
  Future<List<TableLive>> tables(String posProfile) async =>
      _list(await client.get('$_m.waiter.tables', query: {'pos_profile': posProfile})).map(TableLive.fromJson).toList();

  @override
  Future<Order> createOrder(Map<String, dynamic> payload) async =>
      Order.fromJson(_map(await client.post('$_m.waiter.create_order', body: payload)));

  @override
  Future<Order> addItems(Map<String, dynamic> payload) async =>
      Order.fromJson(_map(await client.post('$_m.waiter.add_items', body: payload)));

  @override
  Future<List<Order>> myOrders(String posProfile, {required bool all, int days = 1}) async => _list(await client.get(
        '$_m.waiter.my_orders',
        query: {'pos_profile': posProfile, 'scope': all ? 'all' : 'mine', 'days': '$days'},
      )).map(Order.fromJson).toList();

  @override
  Future<Order> order(String name) async =>
      Order.fromJson(_map(await client.get('$_m.waiter.order', query: {'name': name})));

  @override
  Future<void> cancelOrder(String name, String reason) =>
      client.post('$_m.waiter.cancel_order', body: {'name': name, 'reason': reason});

  @override
  Future<List<GuestCall>> activeCalls(String posProfile) async =>
      _list(await client.get('$_m.calls.active', query: {'pos_profile': posProfile})).map(GuestCall.fromJson).toList();

  @override
  Future<CallAcceptResult> acceptCall(String name) async {
    final r = await client.post('$_m.calls.accept', body: {'name': name});
    if (r is Map) {
      final ok = r['ok'];
      return CallAcceptResult(ok: ok == null || ok == true || ok == 1, acceptedBy: r['accepted_by']?.toString());
    }
    return const CallAcceptResult(ok: true);
  }

  @override
  Future<void> attendCall(String name) => client.post('$_m.calls.attended', body: {'name': name});
}
