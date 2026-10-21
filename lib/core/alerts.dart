import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Where a tapped notification should take the waiter.
enum AlertTarget { calls, orders }

/// Loud, reliable alerts for guest calls and order events.
abstract class Alerts {
  Future<void> init();
  Future<bool> enabled();
  Future<bool> requestPermission();
  Future<void> showCall({required String id, required String title, required String body});
  Future<void> showOrder({required String id, required String title, required String body});
  Future<void> cancel(String id);
  Stream<AlertTarget> get taps;

  /// Handles an FCM data payload (`type`, `name`, `table`, `title`, `body`).
  Future<void> showFromData(Map<String, dynamic> data) async {
    final type = '${data['type'] ?? ''}';
    final id = '${data['name'] ?? type}';
    final title = '${data['title'] ?? ''}';
    final body = '${data['body'] ?? ''}';
    switch (type) {
      case 'waiter_call':
        await showCall(id: id, title: title.isEmpty ? 'Table ${data['table'] ?? ''} is calling' : title, body: body);
      case 'call_taken':
        await cancel(id);
      case 'order_ready' || 'order_accepted' || 'order_rejected':
        await showOrder(id: '$type:$id', title: title.isEmpty ? id : title, body: body);
      default:
        if (title.isNotEmpty) await showOrder(id: id, title: title, body: body);
    }
  }
}

class NoopAlerts extends Alerts {
  final shown = <String>[];
  @override
  Future<void> init() async {}
  @override
  Future<bool> enabled() async => true;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> showCall({required String id, required String title, required String body}) async => shown.add('call:$id');
  @override
  Future<void> showOrder({required String id, required String title, required String body}) async => shown.add('order:$id');
  @override
  Future<void> cancel(String id) async => shown.remove('call:$id');
  @override
  Stream<AlertTarget> get taps => const Stream.empty();
}

const callsChannel = AndroidNotificationChannel(
  'calls',
  'Guest calls',
  description: 'A guest is calling a waiter. Loud, uses the alarm volume.',
  importance: Importance.max,
  playSound: true,
  sound: RawResourceAndroidNotificationSound('call_alert'),
  audioAttributesUsage: AudioAttributesUsage.alarm,
  enableVibration: true,
  enableLights: true,
);

const ordersChannel = AndroidNotificationChannel(
  'orders',
  'Orders',
  description: 'Order ready, accepted or rejected at the till.',
  importance: Importance.high,
  playSound: true,
  enableVibration: true,
);

const generalChannel = AndroidNotificationChannel(
  'general',
  'General',
  description: 'Other messages from ServePOS.',
  importance: Importance.defaultImportance,
);

final _callVibration = Int64List.fromList([0, 600, 300, 600, 300, 600]);

class LocalAlerts extends Alerts {
  LocalAlerts();
  final _plugin = FlutterLocalNotificationsPlugin();
  final _taps = StreamController<AlertTarget>.broadcast();
  final _recent = <String, DateTime>{};
  bool _ready = false;

  @override
  Stream<AlertTarget> get taps => _taps.stream;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<void> init() async {
    if (_ready) return;
    await _plugin.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('ic_stat_notify')),
      onDidReceiveNotificationResponse: (r) => _taps.add(_targetOf(r.payload)),
    );
    final a = _android;
    if (a != null) {
      await a.createNotificationChannel(callsChannel);
      await a.createNotificationChannel(ordersChannel);
      await a.createNotificationChannel(generalChannel);
    }
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      final p = launch!.notificationResponse?.payload;
      scheduleMicrotask(() => _taps.add(_targetOf(p)));
    }
    _ready = true;
  }

  AlertTarget _targetOf(String? payload) => payload == 'calls' ? AlertTarget.calls : AlertTarget.orders;

  @override
  Future<bool> enabled() async => await _android?.areNotificationsEnabled() ?? true;

  @override
  Future<bool> requestPermission() async {
    final a = _android;
    if (a == null) return true;
    final ok = await a.requestNotificationsPermission() ?? false;
    try {
      await a.requestFullScreenIntentPermission();
    } catch (_) {}
    return ok;
  }

  int _idOf(String key) => key.hashCode & 0x7fffffff;

  /// The same call can arrive by push and by polling; alert once per minute.
  bool _dedupe(String key) {
    final now = DateTime.now();
    _recent.removeWhere((_, t) => now.difference(t) > const Duration(minutes: 10));
    final last = _recent[key];
    if (last != null && now.difference(last) < const Duration(minutes: 1)) return false;
    _recent[key] = now;
    return true;
  }

  @override
  Future<void> showCall({required String id, required String title, required String body}) async {
    if (!_dedupe('call:$id')) return;
    await init();
    await _plugin.show(
      _idOf('call:$id'),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          callsChannel.id,
          callsChannel.name,
          channelDescription: callsChannel.description,
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          fullScreenIntent: true,
          playSound: true,
          sound: const RawResourceAndroidNotificationSound('call_alert'),
          audioAttributesUsage: AudioAttributesUsage.alarm,
          enableVibration: true,
          vibrationPattern: _callVibration,
          ticker: title,
          visibility: NotificationVisibility.public,
          autoCancel: true,
        ),
      ),
      payload: 'calls',
    );
  }

  @override
  Future<void> showOrder({required String id, required String title, required String body}) async {
    if (!_dedupe('order:$id')) return;
    await init();
    await _plugin.show(
      _idOf('order:$id'),
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          ordersChannel.id,
          ordersChannel.name,
          channelDescription: ordersChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.status,
          ticker: title,
        ),
      ),
      payload: 'orders',
    );
  }

  @override
  Future<void> cancel(String id) async {
    try {
      await _plugin.cancel(_idOf('call:$id'));
    } catch (e) {
      debugPrint('cancel notification failed: $e');
    }
  }
}
