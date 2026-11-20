import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:servepos_waiter/core/api/api_client.dart';
import 'package:servepos_waiter/core/api/api_exception.dart';
import 'package:servepos_waiter/core/storage.dart';
import 'package:servepos_waiter/features/auth/session_controller.dart';

import 'support/fakes.dart';

String serverMessages(String msg) => jsonEncode({
      'exc_type': 'ValidationError',
      '_server_messages': jsonEncode([jsonEncode({'message': msg, 'indicator': 'red'})]),
    });

void main() {
  group('parseFrappeError / mapHttpError', () {
    test('reads the first _server_messages entry and strips html', () {
      final p = parseFrappeError(serverMessages('Item <b>Fries</b> is not available'));
      expect(p.message, 'Item Fries is not available');
      expect(p.excType, 'ValidationError');
    });

    test('falls back to exception text', () {
      final p = parseFrappeError(jsonEncode({'exception': 'frappe.exceptions.ValidationError: Table is closed'}));
      expect(p.message, 'Table is closed');
    });

    test('401 on an authed call is a session expiry', () {
      expect(mapHttpError(401, '{}'), isA<SessionExpiredException>());
      expect(mapHttpError(403, jsonEncode({'exc_type': 'AuthenticationError'})), isA<SessionExpiredException>());
    });

    test('401 on login is a rejected login with the server text', () {
      final e = mapHttpError(401, jsonEncode({'exc_type': 'AuthenticationError', 'message': 'Incorrect password'}), isLogin: true);
      expect(e, isA<LoginRejectedException>());
      expect(e.message, 'Incorrect password');
    });

    test('429 on login says too many attempts', () {
      expect(mapHttpError(429, '', isLogin: true).message, contains('Too many attempts'));
    });

    test('417 validation is permanent, 5xx and 429 are transient', () {
      final v = mapHttpError(417, serverMessages('Nope'));
      expect(v, isA<ServerException>());
      expect(v.isTransient, isFalse);
      expect(v.message, 'Nope');
      expect(mapHttpError(502, 'Bad gateway').isTransient, isTrue);
      expect(mapHttpError(429, '').isTransient, isTrue);
      expect(const NetworkException().isTransient, isTrue);
    });

    test('403 permission error is not a logout', () {
      expect(mapHttpError(403, jsonEncode({'exc_type': 'PermissionError'})), isA<ServerException>());
    });
  });

  group('ApiClient', () {
    ApiClient client(MockClient mock) => ApiClient(httpClient: mock, retryDelay: Duration.zero)
      ..baseUrl = 'https://x.qa'
      ..token = 'abc';

    test('sends bearer token and unwraps message', () async {
      late http.Request seen;
      final c = client(MockClient((r) async {
        seen = r;
        return http.Response(jsonEncode({'message': {'ok': true}}), 200);
      }));
      final r = await c.post('servepos.api.mobile.auth.logout');
      expect(r, {'ok': true});
      expect(seen.headers['Authorization'], 'Bearer abc');
      expect(seen.url.toString(), 'https://x.qa/api/method/servepos.api.mobile.auth.logout');
    });

    test('GET encodes query params', () async {
      late http.Request seen;
      final c = client(MockClient((r) async {
        seen = r;
        return http.Response(jsonEncode({'message': []}), 200);
      }));
      await c.get('servepos.api.mobile.waiter.tables', query: {'pos_profile': 'Cocktail Bar', 'version': null});
      expect(seen.method, 'GET');
      expect(seen.url.queryParameters, {'pos_profile': 'Cocktail Bar'});
    });

    test('401 calls onSessionExpired and throws SessionExpiredException', () async {
      var expired = 0;
      final c = client(MockClient((r) async => http.Response(jsonEncode({'exc_type': 'AuthenticationError'}), 401)))
        ..onSessionExpired = () => expired++;
      await expectLater(c.get('servepos.api.mobile.auth.me'), throwsA(isA<SessionExpiredException>()));
      expect(expired, 1);
    });

    test('login 401 does not trigger session expiry', () async {
      var expired = 0;
      final c = client(MockClient((r) async => http.Response(jsonEncode({'message': 'Incorrect password'}), 401)))
        ..onSessionExpired = () => expired++;
      await expectLater(c.post('servepos.api.mobile.auth.login', isLogin: true), throwsA(isA<LoginRejectedException>()));
      expect(expired, 0);
    });

    test('GET retries transient failures, then succeeds', () async {
      var n = 0;
      final c = client(MockClient((r) async {
        n++;
        if (n < 3) throw const SocketException('down');
        return http.Response(jsonEncode({'message': 'pong'}), 200);
      }));
      expect(await c.get('frappe.ping'), 'pong');
      expect(n, 3);
    });

    test('POST is never retried by the client', () async {
      var n = 0;
      final c = client(MockClient((r) async {
        n++;
        throw const SocketException('down');
      }));
      await expectLater(c.post('servepos.api.mobile.waiter.create_order'), throwsA(isA<NetworkException>()));
      expect(n, 1);
    });

    test('reports reachability', () async {
      final seen = <bool>[];
      final c = client(MockClient((r) async => throw const SocketException('down')))
        ..onReachability = seen.add;
      await expectLater(c.post('x'), throwsA(isA<NetworkException>()));
      expect(seen, [false]);
    });
  });

  group('session expiry end to end', () {
    test('401 anywhere wipes the token and returns to login with a message', () async {
      final api = FakeWaiterApi();
      final secure = MemoryStore({
        SecureKeys.server: 'https://erp.example.com',
        SecureKeys.token: 'tok-1',
        SecureKeys.session: jsonEncode(loginJson()..remove('token')),
      });
      final s = fakeServices(api: api, secure: secure);
      await s.init();
      expect(s.session.stage, AuthStage.ready);
      api.expireNext = true;
      await expectLater(s.floor.api.tables('Cocktail Bar'), throwsA(isA<SessionExpiredException>()));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(s.session.stage, AuthStage.needLogin);
      expect(s.session.loginMessage, 'session_ended');
      expect(await secure.read(SecureKeys.token), isNull);
      expect(api.token, isNull);
      // Server URL and device id survive.
      expect(await secure.read(SecureKeys.server), 'https://erp.example.com');
    });
  });
}
