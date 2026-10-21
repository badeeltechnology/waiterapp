import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'api_exception.dart';

/// Thin HTTP layer for Frappe `/api/method/...` calls.
///
/// - Adds `Authorization: Bearer <token>` when a token is set.
/// - Unwraps `{"message": ...}`.
/// - Maps failures to [ApiException]s; a 401 calls [onSessionExpired] once.
/// - Timeout on every call; GETs retry twice on transient errors.
class ApiClient {
  ApiClient({
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
    this.getRetries = 2,
    this.retryDelay = const Duration(milliseconds: 600),
  }) : _http = httpClient ?? http.Client();

  final http.Client _http;
  final Duration timeout;
  final int getRetries;
  final Duration retryDelay;

  String? baseUrl;
  String? token;
  String userAgent = 'ServePOS-Waiter';

  /// Called when an authenticated request comes back 401/AuthenticationError.
  void Function()? onSessionExpired;

  /// Called after every request: true if the server answered at all.
  void Function(bool reachable)? onReachability;

  Uri _uri(String method, [Map<String, dynamic>? query]) {
    final base = baseUrl;
    if (base == null || base.isEmpty) throw const NetworkException('No server set.');
    final q = query == null
        ? null
        : {
            for (final e in query.entries)
              if (e.value != null) e.key: e.value is String ? e.value as String : jsonEncode(e.value),
          };
    return Uri.parse('$base/api/method/$method').replace(queryParameters: (q == null || q.isEmpty) ? null : q);
  }

  Map<String, String> _headers({bool json = false, String? overrideToken}) => {
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json; charset=utf-8',
        'User-Agent': userAgent,
        if ((overrideToken ?? token) != null) 'Authorization': 'Bearer ${overrideToken ?? token}',
      };

  Future<dynamic> get(String method, {Map<String, dynamic>? query, bool retry = true}) async {
    var attempt = 0;
    while (true) {
      try {
        return await _send(() => _http.get(_uri(method, query), headers: _headers()), authed: true);
      } on ApiException catch (e) {
        if (!retry || !e.isTransient || attempt >= getRetries) rethrow;
        attempt++;
        await Future<void>.delayed(retryDelay * attempt);
      }
    }
  }

  /// POST is never retried here: order-creating calls go through the outbox,
  /// which retries with the same client_request_id.
  Future<dynamic> post(String method, {Map<String, dynamic>? body, bool isLogin = false, String? overrideToken}) {
    return _send(
      () => _http.post(
        _uri(method),
        headers: _headers(json: true, overrideToken: overrideToken),
        body: jsonEncode(body ?? const {}),
      ),
      authed: !isLogin && overrideToken == null,
      isLogin: isLogin,
    );
  }

  /// Unauthenticated reachability check used by the server URL screen.
  Future<bool> ping(String base) async {
    final uri = Uri.parse('$base/api/method/frappe.ping');
    final res = await _guard(() => _http.get(uri, headers: {'Accept': 'application/json'}));
    if (res.statusCode != 200) return false;
    try {
      final m = jsonDecode(res.body);
      return m is Map && m['message'] == 'pong';
    } catch (_) {
      return false;
    }
  }

  Future<http.Response> _guard(Future<http.Response> Function() call) async {
    try {
      final res = await call().timeout(timeout);
      onReachability?.call(true);
      return res;
    } on TimeoutException {
      onReachability?.call(false);
      throw const TimeoutApiException();
    } on HandshakeException {
      onReachability?.call(false);
      throw const NetworkException('Secure connection failed. Check the server address.');
    } on SocketException {
      onReachability?.call(false);
      throw const NetworkException();
    } on http.ClientException {
      onReachability?.call(false);
      throw const NetworkException();
    } on HttpException {
      onReachability?.call(false);
      throw const NetworkException();
    } on StateError catch (e) {
      // dart:io on Android: "Insecure HTTP is not allowed by platform".
      if (e.message.contains('Insecure HTTP')) {
        throw const NetworkException('This app only connects to https servers.');
      }
      rethrow;
    }
  }

  Future<dynamic> _send(Future<http.Response> Function() call, {required bool authed, bool isLogin = false}) async {
    final res = await _guard(call);
    final body = utf8.decode(res.bodyBytes, allowMalformed: true);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (body.isEmpty) return null;
      final Object? decoded;
      try {
        decoded = jsonDecode(body);
      } catch (_) {
        throw const BadResponseException();
      }
      if (decoded is Map && decoded.containsKey('message')) return decoded['message'];
      return decoded;
    }
    final err = mapHttpError(res.statusCode, body, isLogin: isLogin);
    if (err is SessionExpiredException && authed) {
      onSessionExpired?.call();
    }
    throw err;
  }

  void close() => _http.close();
}
