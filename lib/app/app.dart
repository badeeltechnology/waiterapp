import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../core/alerts.dart';
import '../core/api/waiter_api.dart';
import '../core/platform.dart';
import '../core/push.dart';
import '../core/theme.dart';
import '../features/auth/auth_screens.dart';
import '../features/auth/session_controller.dart';
import '../features/calls/calls_controller.dart';
import '../features/floor/floor_controller.dart';
import '../features/home/home_shell.dart';
import '../features/order/cart.dart';
import '../features/order/menu_repository.dart';
import '../features/order/order_sender.dart';
import '../features/order/outbox.dart';
import '../features/orders/orders_controller.dart';
import '../features/settings/app_settings.dart';
import '../features/order/send_controller.dart';
import 'nav.dart';
import 'notices.dart';
import 'overlay_host.dart';
import 'services.dart';

export 'nav.dart' show rootNavigatorKey;

class WaiterApp extends StatelessWidget {
  const WaiterApp({super.key, required this.services});
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final s = services;
    return MultiProvider(
      providers: [
        Provider<AppServices>.value(value: s),
        Provider<WaiterApi>.value(value: s.api),
        Provider<BiometricGate>.value(value: s.biometric),
        Provider<Alerts>.value(value: s.alerts),
        Provider<PushService>.value(value: s.push),
        Provider<OrderSender>.value(value: s.sender),
        ChangeNotifierProvider<NetStatus>.value(value: s.net),
        ChangeNotifierProvider<AppSettings>.value(value: s.settings),
        ChangeNotifierProvider<SessionController>.value(value: s.session),
        ChangeNotifierProvider<MenuRepository>.value(value: s.menu),
        ChangeNotifierProvider<FloorController>.value(value: s.floor),
        ChangeNotifierProvider<OrdersController>.value(value: s.orders),
        ChangeNotifierProvider<CallsController>.value(value: s.calls),
        ChangeNotifierProvider<CartStore>.value(value: s.carts),
        ChangeNotifierProvider<Outbox>.value(value: s.outbox),
        ChangeNotifierProvider<SendController>.value(value: s.sending),
        ChangeNotifierProvider<Notices>.value(value: s.notices),
      ],
      child: Consumer<AppSettings>(
        builder: (context, settings, _) => MaterialApp(
          title: 'ServePOS Waiter',
          debugShowCheckedModeBanner: false,
          theme: Nami.theme(),
          locale: Locale(settings.language),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          navigatorKey: rootNavigatorKey,
          builder: (context, child) => OverlayHost(child: child ?? const SizedBox.shrink()),
          home: const RootGate(),
        ),
      ),
    );
  }
}

/// Shows the screen for the current auth stage and handles idle lock.
class RootGate extends StatefulWidget {
  const RootGate({super.key});
  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  late final AppLifecycleListener _life;
  AuthStage? _lastStage;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(onHide: _onHide, onShow: _onShow);
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  void _onHide() {
    final s = context.read<AppServices>();
    s.session.markBackground();
    s.floor.pause();
    s.calls.stopPolling();
    s.orders.stopPolling();
  }

  void _onShow() {
    final s = context.read<AppServices>();
    if (s.session.maybeLockOnResume()) return;
    if (s.session.stage == AuthStage.ready) {
      s.floor.resume();
      s.calls.startPolling();
      s.orders.resumePolling();
      s.floor.refresh();
      s.calls.refresh();
      s.orders.refresh();
      s.outbox.flush(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stage = context.select<SessionController, AuthStage>((s) => s.stage);
    if (_lastStage == AuthStage.ready && stage != AuthStage.ready) {
      // Leaving the signed-in area: drop any pushed screens (take order, detail).
      WidgetsBinding.instance.addPostFrameCallback((_) => rootNavigatorKey.currentState?.popUntil((r) => r.isFirst));
    }
    _lastStage = stage;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: switch (stage) {
        AuthStage.loading => const _Splash(key: ValueKey('splash')),
        AuthStage.needServer => const ServerUrlScreen(key: ValueKey('server')),
        AuthStage.needLogin => const LoginScreen(key: ValueKey('login')),
        AuthStage.locked => const LockScreen(key: ValueKey('lock')),
        AuthStage.needProfile => const ProfilePickerScreen(key: ValueKey('profile')),
        AuthStage.ready => const HomeShell(key: ValueKey('home')),
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: Nami.deep,
    body: Center(child: CircularProgressIndicator(color: Nami.amber)),
  );
}
