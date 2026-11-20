import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:servepos_waiter/app/services.dart';
import 'package:servepos_waiter/core/api/api_exception.dart';
import 'package:servepos_waiter/core/server_url.dart';
import 'package:servepos_waiter/core/storage.dart';
import 'package:servepos_waiter/features/auth/session_controller.dart';

import 'support/fakes.dart';

void stopTimers(AppServices s) {
  s.floor.setVisible(false);
  s.calls.stopPolling();
  s.outbox.stop();
}

void main() {
  test('first run asks for the server', () async {
    final s = fakeServices();
    await s.init();
    expect(s.session.stage, AuthStage.needServer);
  });

  test('server check: normalises, pings, refuses public http', () async {
    final api = FakeWaiterApi();
    final s = fakeServices(api: api);
    await s.init();
    final n = await s.session.checkServer('erp.example.com/app/home');
    expect(n.url, 'https://erp.example.com');
    expect(api.calls, contains('ping https://erp.example.com'));
    expect(() => s.session.checkServer('http://erp.example.com'), throwsA(isA<ServerUrlException>().having((e) => e.message, 'm', 'http_public')));
    expect(() => s.session.checkServer('http://192.168.1.5:8000'), throwsA(isA<ServerUrlException>().having((e) => e.message, 'm', 'http_local')));
    expect((await s.session.checkServer('http://192.168.1.5:8000', insecureConfirmed: true)).url, 'http://192.168.1.5:8000');
    api.pingOk = false;
    expect(() => s.session.checkServer('https://wrong.qa'), throwsA(isA<ServerUrlException>().having((e) => e.message, 'm', 'unreachable')));
  });

  test('login stores the token securely, never the password, and sends device facts', () async {
    final api = FakeWaiterApi();
    final secure = MemoryStore();
    final s = fakeServices(api: api, secure: secure);
    await s.init();
    await s.session.setServer(normalizeServerUrl('https://erp.example.com'));
    await expectLater(s.session.login('ahmed@example.com', 'wrong'), throwsA(isA<LoginRejectedException>()));
    await s.session.login('ahmed@example.com', 'secret');
    expect(s.session.stage, AuthStage.ready, reason: 'single profile is picked automatically');
    expect(await secure.read(SecureKeys.token), 'tok-1');
    expect(secure.data.values.any((v) => v.contains('secret')), isFalse);
    expect(await secure.read(DeviceFactsProviderKey.id), isNotNull);
    expect(api.calls, contains('login ahmed@example.com true'));
    expect(s.session.pendingBiometricOffer, isTrue);
    stopTimers(s);
  });

  test('several profiles: picker, then the choice is remembered', () async {
    final api = FakeWaiterApi()..loginResponse = loginJson(profiles: ['Cocktail Bar', 'Beach Grill']);
    final secure = MemoryStore();
    final prefs = MemoryStore();
    final s = fakeServices(api: api, secure: secure, prefs: prefs);
    await s.init();
    await s.session.setServer(normalizeServerUrl('erp.example.com'));
    await s.session.login('ahmed@example.com', 'secret');
    expect(s.session.stage, AuthStage.needProfile);
    await s.session.chooseProfile(s.session.session!.profiles[1]);
    expect(s.session.stage, AuthStage.ready);
    stopTimers(s);

    // Restart: goes straight in with the remembered outlet.
    final s2 = fakeServices(api: api, secure: secure, prefs: prefs);
    await s2.init();
    expect(s2.session.stage, AuthStage.ready);
    expect(s2.session.profile!.name, 'Beach Grill');
    stopTimers(s2);
  });

  test('biometric lock on launch; password fallback revokes the old token after re-login', () async {
    final api = FakeWaiterApi();
    final bio = FakeBiometric(succeed: false);
    final secure = MemoryStore({
      SecureKeys.server: 'https://erp.example.com',
      SecureKeys.token: 'old-token',
      SecureKeys.session: jsonEncode(loginJson()..remove('token')),
    });
    final prefs = MemoryStore({'biometric': '1'});
    final s = fakeServices(api: api, secure: secure, prefs: prefs, biometric: bio);
    await s.init();
    expect(s.session.stage, AuthStage.locked);
    expect(api.calls.where((c) => c != 'ping'), isEmpty, reason: 'token not used before unlock');
    expect(await s.session.unlock('r'), isFalse);
    expect(s.session.stage, AuthStage.locked);

    await s.session.usePasswordInstead();
    expect(s.session.stage, AuthStage.needLogin);
    expect(await secure.read(SecureKeys.token), isNull);
    await s.session.login('ahmed@example.com', 'secret');
    expect(api.calls, contains('logout old-token'));
    stopTimers(s);
  });

  test('biometric unlock succeeds', () async {
    final s = fakeServices(
      secure: MemoryStore({
        SecureKeys.server: 'https://erp.example.com',
        SecureKeys.token: 't',
        SecureKeys.session: jsonEncode(loginJson()..remove('token')),
      }),
      prefs: MemoryStore({'biometric': '1'}),
    );
    await s.init();
    expect(await s.session.unlock('r'), isTrue);
    expect(s.session.stage, AuthStage.ready);
    stopTimers(s);
  });

  test('idle timeout locks on resume only after the configured minutes', () async {
    var now = DateTime(2026, 10, 21, 12);
    final api = FakeWaiterApi();
    final secure = MemoryStore({
      SecureKeys.server: 'https://erp.example.com',
      SecureKeys.token: 't',
      SecureKeys.session: jsonEncode(loginJson()..remove('token')),
    });
    final prefs = MemoryStore({'biometric': '1', 'idle_minutes': '5'});
    final s = fakeServices(api: api, secure: secure, prefs: prefs);
    final session = SessionController(
      api: api,
      secure: secure,
      settings: s.settings,
      biometric: FakeBiometric(),
      deviceFacts: FakeDeviceFacts(secure),
      clock: () => now,
    );
    await s.settings.load();
    await session.init();
    await session.unlock('r');
    expect(session.stage, AuthStage.ready);
    session.markBackground();
    now = now.add(const Duration(minutes: 4));
    expect(session.maybeLockOnResume(), isFalse);
    session.markBackground();
    now = now.add(const Duration(minutes: 5));
    expect(session.maybeLockOnResume(), isTrue);
    expect(session.stage, AuthStage.locked);
  });

  test('sign out calls logout and wipes token, drafts and queue', () async {
    final api = FakeWaiterApi();
    final secure = MemoryStore();
    final s = fakeServices(api: api, secure: secure);
    await s.init();
    await s.session.setServer(normalizeServerUrl('erp.example.com'));
    await s.session.login('ahmed@example.com', 'secret');
    await s.settings.setBiometric(true);
    s.carts.setGuests('table:T1', 2);
    await s.session.signOut();
    expect(api.calls, contains('logout tok-1'));
    expect(await secure.read(SecureKeys.token), isNull);
    expect(await secure.read(SecureKeys.session), isNull);
    expect(s.settings.biometricEnabled, isFalse);
    expect(s.carts.draftKeys, isEmpty);
    expect(s.session.stage, AuthStage.needLogin);
  });

  test('offline launch keeps the cached session', () async {
    final api = FakeWaiterApi()..meError = const NetworkException();
    final s = fakeServices(
      api: api,
      secure: MemoryStore({
        SecureKeys.server: 'https://erp.example.com',
        SecureKeys.token: 't',
        SecureKeys.session: jsonEncode(loginJson()..remove('token')),
      }),
    );
    await s.init();
    await Future<void>.delayed(Duration.zero);
    expect(s.session.stage, AuthStage.ready);
    stopTimers(s);
  });
}

/// Mirrors the private key name in DeviceFactsProvider.
class DeviceFactsProviderKey {
  static const id = 'device_id';
}
