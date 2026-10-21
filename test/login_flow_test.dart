import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servepos_waiter/app/app.dart';
import 'package:servepos_waiter/app/services.dart';
import 'package:servepos_waiter/core/storage.dart';
import 'package:servepos_waiter/features/auth/session_controller.dart';
import 'package:servepos_waiter/features/home/home_shell.dart';

import 'support/fakes.dart';

void main() {
  void stopTimers(AppServices s) {
    s.floor.setVisible(false);
    s.calls.stopPolling();
    s.outbox.stop();
  }

  testWidgets('server URL -> password -> outlet -> floor -> fingerprint offer', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final api = FakeWaiterApi()..loginResponse = loginJson(profiles: ['Cocktail Bar', 'Beach Grill']);
    final secure = MemoryStore();
    final bio = FakeBiometric();
    final s = fakeServices(api: api, secure: secure, biometric: bio);
    await s.init();
    await tester.pumpWidget(WaiterApp(services: s));
    await tester.pumpAndSettle();

    // 1. Server URL
    expect(find.text('Connect to your restaurant'), findsOneWidget);
    // https:// is shown in front of the field, so waiters only type the address.
    Text scheme() => tester.widget<Text>(find.byKey(const Key('server_scheme')));
    TextField field() => tester.widget<TextField>(find.byKey(const Key('server_field')));
    expect(scheme().data, 'https://');
    await tester.enterText(find.byKey(const Key('server_field')), 'https://demo.myapp.qa');
    await tester.pump();
    expect(field().controller!.text, 'demo.myapp.qa', reason: 'a typed scheme moves into the prefix');
    expect(scheme().data, 'https://');
    await tester.enterText(find.byKey(const Key('server_field')), 'http://demo.myapp.qa');
    await tester.pump();
    expect(scheme().data, 'http://');
    await tester.tap(find.byKey(const Key('server_continue')));
    await tester.pumpAndSettle();
    expect(find.textContaining('not secure'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('server_field')), '');
    await tester.pump();
    expect(scheme().data, 'https://', reason: 'clearing the field goes back to https');
    await tester.enterText(find.byKey(const Key('server_field')), 'demo.myapp.qa/app/home');
    await tester.tap(find.byKey(const Key('server_continue')));
    await tester.pumpAndSettle();
    expect(s.session.serverUrl, 'https://demo.myapp.qa');

    // 2. Password: wrong first.
    expect(find.byKey(const Key('login_user')), findsOneWidget);
    expect(find.text('demo.myapp.qa'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('login_user')), 'ahmed@example.com');
    await tester.enterText(find.byKey(const Key('login_password')), 'wrong');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();
    expect(find.text('Incorrect password'), findsOneWidget);
    expect(s.session.stage, AuthStage.needLogin);

    await tester.enterText(find.byKey(const Key('login_password')), 'secret');
    await tester.tap(find.byKey(const Key('login_submit')));
    await tester.pumpAndSettle();

    // 3. Outlet picker
    expect(find.text('Choose your outlet'), findsOneWidget);
    await tester.tap(find.byKey(const Key('profile_Beach Grill')));
    await tester.pumpAndSettle();

    // 4. Home + fingerprint offer
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.text('Use fingerprint to unlock next time?'), findsOneWidget);
    await tester.tap(find.text('Use fingerprint'));
    await tester.pumpAndSettle();
    expect(s.settings.biometricEnabled, isTrue);
    expect(bio.prompts, 1);
    expect(await secure.read(SecureKeys.token), 'tok-1');
    expect(secure.data.values.any((v) => v.contains('secret')), isFalse);
    expect(api.calls, containsAll(['bootstrap', 'tables', 'orders', 'calls']));

    // Push not configured in tests: Account says so instead of failing.
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    expect(find.text('Push alerts off'), findsOneWidget);

    // 5. Session ends on the server -> back to login with the message.
    api.expireNext = true;
    await s.floor.refresh();
    await tester.pumpAndSettle();
    expect(find.text('Your session ended. Please sign in again.'), findsOneWidget);
    expect(await secure.read(SecureKeys.token), isNull);

    stopTimers(s);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('lock screen: fallback to password', (tester) async {
    final secure = MemoryStore({
      SecureKeys.server: 'https://demo.myapp.qa',
      SecureKeys.token: 'old',
      SecureKeys.session: '{"user":{"user":"ahmed@example.com","full_name":"Ahmed Khalil","waiter":"Ahmed"},"pos_profiles":[{"name":"Cocktail Bar"}]}',
    });
    final s = fakeServices(secure: secure, prefs: MemoryStore({'biometric': '1'}), biometric: FakeBiometric(succeed: false));
    await s.init();
    await tester.pumpWidget(WaiterApp(services: s));
    await tester.pumpAndSettle();
    expect(find.text('Ahmed Khalil'), findsOneWidget);
    expect(find.text('Not recognised. Try again.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('lock_password')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login_password')), findsOneWidget);
    stopTimers(s);
    await tester.pumpWidget(const SizedBox());
  });
}
