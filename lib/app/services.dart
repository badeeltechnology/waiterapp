import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/alerts.dart';
import '../core/api/api_client.dart';
import '../core/api/waiter_api.dart';
import '../core/models/order.dart';
import '../core/platform.dart';
import '../core/push.dart';
import '../core/storage.dart';
import '../features/auth/session_controller.dart';
import '../features/calls/calls_controller.dart';
import '../features/floor/floor_controller.dart';
import '../features/order/cart.dart';
import '../features/order/menu_repository.dart';
import '../features/order/order_sender.dart';
import '../features/order/outbox.dart';
import '../features/order/send_controller.dart';
import 'notices.dart';
import '../features/orders/orders_controller.dart';
import '../features/settings/app_settings.dart';

/// Set by --dart-define=LOCAL_TEST=true for the office test APK (plain http to a local server).
const bool kLocalTestBuild = bool.fromEnvironment('LOCAL_TEST');

/// Everything the app needs, built once. Tests build it with fakes.
class AppServices {
  AppServices({
    required this.api,
    required this.secure,
    required this.prefs,
    required this.json,
    required this.biometric,
    required this.alerts,
    required this.push,
    required this.net,
    DeviceFactsProvider? facts,
    SendFeedback? feedback,
    bool? allowInsecureLocal,
    bool? httpsOnly,
  }) : facts = facts ?? DeviceFactsProvider(secure) {
    settings = AppSettings(prefs);
    session = SessionController(
      api: api,
      secure: secure,
      settings: settings,
      biometric: biometric,
      deviceFacts: this.facts,
      allowInsecureLocal: allowInsecureLocal ?? (kDebugMode || kLocalTestBuild),
      httpsOnly: httpsOnly ?? (kReleaseMode && !kLocalTestBuild),
    );
    menu = MenuRepository(api: api, store: json);
    floor = FloorController(api: api);
    orders = OrdersController(api: api, alerts: alerts);
    calls = CallsController(api: api, alerts: alerts);
    carts = CartStore(store: json);
    outbox = Outbox(sender: OrderSender.senderFor(api), store: json);
    sender = OrderSender(carts: carts, outbox: outbox);
    sending = SendController(sender: sender, outbox: outbox, feedback: feedback);
    notices = Notices();
    _wire();
  }

  final WaiterApi api;
  final KeyValueStore secure;
  final KeyValueStore prefs;
  final JsonStore json;
  final BiometricGate biometric;
  final Alerts alerts;
  final PushService push;
  final NetStatus net;
  final DeviceFactsProvider facts;

  late final AppSettings settings;
  late final SessionController session;
  late final MenuRepository menu;
  late final FloorController floor;
  late final OrdersController orders;
  late final CallsController calls;
  late final CartStore carts;
  late final Outbox outbox;
  late final OrderSender sender;
  late final SendController sending;
  late final Notices notices;
  final List<StreamSubscription<Object?>> _subs = [];

  static Future<AppServices> production() async {
    final client = ApiClient();
    final net = NetStatus();
    client.onReachability = net.report;
    final p = await FirebasePush.create();
    final alerts = LocalAlerts();
    return AppServices(
      api: HttpWaiterApi(client),
      secure: SecureStore(),
      prefs: PrefsStore(),
      json: FileJsonStore(),
      biometric: LocalAuthGate(),
      alerts: alerts,
      push: p ?? NoopPush(),
      net: net,
    );
  }

  void _wire() {
    session.onReady.add(() async {
      final profile = session.profile!.name;
      final user = session.user!;
      outbox.currentUser = user.user;
      await outbox.dropOthers(user.user);
      sender.reconcile();
      outbox.start();
      unawaited(outbox.flush(force: true));
      unawaited(menu.open(profile));
      floor.open(profile);
      orders.open(profile);
      orders.startPolling();
      calls.open(profile, user.waiter);
      final facts = await this.facts.facts();
      unawaited(push.register(api, facts.platform));
    });
    session.onSignedOut.add(({required bool wipe}) async {
      outbox.stop();
      sending.clear();
      notices.clear();
      calls.clear();
      floor.clear();
      orders.clear();
      await push.unregister();
      if (wipe) {
        await carts.wipe();
        await outbox.wipe();
        await menu.wipe();
      }
    });
    net.onBackOnline = () {
      if (session.stage != AuthStage.ready) return;
      outbox.flush(force: true);
      floor.refresh();
      orders.refresh();
      calls.refresh();
    };
    outbox.onSent = (entry, order) {
      orders.upsert(order);
      floor.markOrder(order);
      floor.refresh();
      sending.onOutboxSent(entry, order);
    };
    orders.onStatusChange = (order, from) {
      floor.refresh(); // the table tile shows the new status at once
      final where = order.isTakeaway ? 'Takeaway ${order.name}' : (order.table ?? order.name);
      switch (order.status) {
        case OrderStatus.accepted:
          notices.show(Notice(kind: NoticeKind.accepted, title: where, order: order.name));
        case OrderStatus.ready:
          notices.show(Notice(kind: NoticeKind.ready, title: where, order: order.name));
        case OrderStatus.rejected:
          notices.show(Notice(kind: NoticeKind.rejected, title: where, order: order.name));
        default:
      }
    };
    _subs.add(push.messages.listen(_onPush));
  }

  Future<void> _onPush(Map<String, dynamic> data) async {
    await alerts.showFromData(data);
    switch ('${data['type'] ?? ''}') {
      case 'waiter_call' || 'call_taken':
        await calls.refresh();
      case 'order_ready' || 'order_accepted' || 'order_rejected':
        await orders.refresh();
        await floor.refresh();
    }
  }

  Future<void> init() async {
    await settings.load();
    await carts.load();
    await outbox.load();
    try {
      await alerts.init();
    } catch (e) {
      debugPrint('alerts init failed: $e');
    }
    await session.init();
  }
}
