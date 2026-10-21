import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'alerts.dart';
import 'api/waiter_api.dart';

/// FCM background isolate entry: show the alert ourselves (data messages carry
/// no notification block, so Android would otherwise show nothing).
@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  final alerts = LocalAlerts();
  await alerts.init();
  await alerts.showFromData(message.data);
}

/// Push messaging. Optional: if Firebase is not configured the app still works
/// with polling.
abstract class PushService {
  /// False when Firebase could not start (e.g. google-services.json does not
  /// match this app id). The app then relies on polling while open.
  bool get available;

  /// Data messages received while the app is open.
  Stream<Map<String, dynamic>> get messages;

  /// Data payloads from notifications that opened the app.
  Stream<Map<String, dynamic>> get opened;
  Future<void> register(WaiterApi api, String platform);
  Future<void> unregister();
}

class NoopPush implements PushService {
  @override
  bool get available => false;
  @override
  Stream<Map<String, dynamic>> get messages => const Stream.empty();
  @override
  Stream<Map<String, dynamic>> get opened => const Stream.empty();
  @override
  Future<void> register(WaiterApi api, String platform) async {}
  @override
  Future<void> unregister() async {}
}

class FirebasePush implements PushService {
  FirebasePush._();

  /// Returns null when Firebase cannot start (no google-services.json etc.).
  static Future<FirebasePush?> create() async {
    try {
      await Firebase.initializeApp().timeout(const Duration(seconds: 8));
      FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
      final p = FirebasePush._();
      p._wire();
      return p;
    } catch (e) {
      debugPrint('Push disabled: $e');
      return null;
    }
  }

  @override
  bool get available => true;

  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  final _opened = StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription<String>? _refreshSub;

  void _wire() {
    FirebaseMessaging.onMessage.listen((m) => _messages.add(m.data));
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _opened.add(m.data));
    FirebaseMessaging.instance.getInitialMessage().then((m) {
      if (m != null) _opened.add(m.data);
    }, onError: (Object e) => debugPrint('getInitialMessage failed: $e'));
  }

  @override
  Stream<Map<String, dynamic>> get messages => _messages.stream;
  @override
  Stream<Map<String, dynamic>> get opened => _opened.stream;

  @override
  Future<void> register(WaiterApi api, String platform) async {
    try {
      final fm = FirebaseMessaging.instance;
      await fm.setAutoInitEnabled(true);
      final token = await fm.getToken();
      if (token != null) await api.registerPush(token, platform);
      await _refreshSub?.cancel();
      _refreshSub = fm.onTokenRefresh.listen((t) {
        api.registerPush(t, platform).catchError((Object e) => debugPrint('push re-register failed: $e'));
      });
    } catch (e) {
      debugPrint('push register failed: $e');
    }
  }

  @override
  Future<void> unregister() async {
    await _refreshSub?.cancel();
    _refreshSub = null;
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }
}
