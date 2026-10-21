import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/alerts.dart';
import '../../core/i18n.dart';
import '../../core/platform.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../auth/session_controller.dart';
import '../calls/calls_controller.dart';
import '../calls/calls_screen.dart';
import '../floor/floor_controller.dart';
import '../floor/floor_screen.dart';
import '../order/outbox.dart';
import '../orders/orders_controller.dart';
import '../orders/orders_screen.dart';
import '../orders/outbox_sheet.dart';
import '../settings/settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialTab = 0});
  final int initialTab;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late int _tab = widget.initialTab;
  StreamSubscription<AlertTarget>? _tapSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncFloorTimer();
      _maybeOfferBiometric();
    });
    final alerts = context.read<Alerts>();
    _tapSub = alerts.taps.listen((t) => _go(t == AlertTarget.calls ? 2 : 1));
  }

  @override
  void dispose() {
    _tapSub?.cancel();
    super.dispose();
  }

  void _go(int i) {
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    setState(() => _tab = i);
    _syncFloorTimer();
  }

  void _syncFloorTimer() {
    if (!mounted) return;
    context.read<FloorController>().setVisible(_tab == 0);
  }

  Future<void> _maybeOfferBiometric() async {
    final session = context.read<SessionController>();
    if (!session.pendingBiometricOffer) return;
    session.pendingBiometricOffer = false;
    final yes = await confirmDialog(
      context,
      title: context.t('bio_offer_title'),
      body: context.t('bio_offer_body'),
      confirm: context.t('bio_offer_yes'),
    );
    if (yes && mounted) {
      await session.setBiometric(true, context.t('lock_reason'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final calls = context.watch<CallsController>();
    final orders = context.watch<OrdersController>();
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(0); // back from Orders/Calls/Account goes to Floor, not out of the app
      },
      child: Scaffold(
        body: Column(children: [
          const _StatusBanners(),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: _StatusBanners.isVisible(context),
              child: IndexedStack(
                index: _tab,
                children: const [FloorScreen(), OrdersScreen(), CallsScreen(), SettingsScreen()],
              ),
            ),
          ),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: _go,
          destinations: [
            NavigationDestination(icon: const Icon(Icons.table_restaurant_outlined), selectedIcon: const Icon(Icons.table_restaurant), label: context.t('nav_floor')),
            NavigationDestination(
              icon: Badge(isLabelVisible: orders.readyUnseen.isNotEmpty, label: Text('${orders.readyUnseen.length}'), backgroundColor: Nami.green, child: const Icon(Icons.receipt_long_outlined)),
              selectedIcon: const Icon(Icons.receipt_long),
              label: context.t('nav_orders'),
            ),
            NavigationDestination(
              icon: Badge(isLabelVisible: calls.waitingCount > 0, label: Text('${calls.waitingCount}'), backgroundColor: Nami.red, child: const Icon(Icons.notifications_active_outlined)),
              selectedIcon: Badge(isLabelVisible: calls.waitingCount > 0, label: Text('${calls.waitingCount}'), backgroundColor: Nami.red, child: const Icon(Icons.notifications_active)),
              label: context.t('nav_calls'),
            ),
            NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: context.t('nav_account')),
          ],
        ),
      ),
    );
  }
}

/// Offline + unsent orders. Always visible above every tab.
class _StatusBanners extends StatelessWidget {
  const _StatusBanners();

  static bool isVisible(BuildContext context) {
    final net = context.watch<NetStatus>();
    final outbox = context.watch<Outbox>();
    return !net.online || outbox.count > 0;
  }

  @override
  Widget build(BuildContext context) {
    final net = context.watch<NetStatus>();
    final outbox = context.watch<Outbox>();
    final top = MediaQuery.paddingOf(context).top;
    final strips = <Widget>[
      if (!net.online) StatusStrip(text: context.t('offline_banner'), color: Nami.ink, icon: Icons.cloud_off),
      if (outbox.failedCount > 0)
        StatusStrip(
          key: const Key('outbox_failed_strip'),
          text: context.t('outbox_failed', {'n': outbox.failedCount}),
          color: Nami.red,
          icon: Icons.error_outline,
          onTap: () => showOutboxSheet(context),
        ),
      if (outbox.waitingCount > 0)
        StatusStrip(
          key: const Key('outbox_waiting_strip'),
          text: context.t('outbox_waiting', {'n': outbox.waitingCount}),
          color: Nami.amber,
          textColor: Nami.ink,
          icon: Icons.schedule_send,
          onTap: () => showOutboxSheet(context),
        ),
    ];
    if (strips.isEmpty) return const SizedBox.shrink();
    return Container(
      color: strips.length == 1 && !net.online ? Nami.ink : Nami.deep,
      padding: EdgeInsets.only(top: top),
      child: MediaQuery.removePadding(context: context, removeTop: true, child: Column(children: strips)),
    );
  }
}
