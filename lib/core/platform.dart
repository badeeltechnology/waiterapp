import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import 'api/waiter_api.dart';
import 'storage.dart';

/// Fingerprint / face / device PIN gate.
abstract class BiometricGate {
  Future<bool> isAvailable();
  Future<bool> authenticate(String reason);
}

class LocalAuthGate implements BiometricGate {
  final _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    try {
      // True when the phone has a fingerprint/face sensor or a screen lock.
      return await _auth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        // biometricOnly false: device PIN/pattern is an accepted fallback.
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true, sensitiveTransaction: true),
      );
    } on PlatformException {
      return false;
    }
  }
}

/// Builds the device facts sent with login. The device id is a UUID made once
/// and kept in secure storage (survives sign-out so the server can recognise
/// the phone; wiped only when the app is uninstalled or data cleared).
class DeviceFactsProvider {
  DeviceFactsProvider(this.secure);
  final KeyValueStore secure;
  static const deviceIdKey = 'device_id';

  Future<String> deviceId() async {
    var id = await secure.read(deviceIdKey);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await secure.write(deviceIdKey, id);
    }
    return id;
  }

  Future<DeviceFacts> facts() async {
    var name = 'Phone';
    var platform = defaultTargetPlatform.name;
    try {
      if (Platform.isAndroid) {
        final a = await DeviceInfoPlugin().androidInfo;
        name = '${a.manufacturer} ${a.model}'.trim();
        platform = 'Android ${a.version.release}';
      } else if (Platform.isIOS) {
        final i = await DeviceInfoPlugin().iosInfo;
        name = i.name;
        platform = 'iOS ${i.systemVersion}';
      }
    } catch (_) {}
    var version = '0.0.0';
    try {
      final p = await PackageInfo.fromPlatform();
      version = '${p.version}+${p.buildNumber}';
    } catch (_) {}
    return DeviceFacts(deviceId: await deviceId(), deviceName: name, platform: platform, appVersion: version);
  }
}

/// FLAG_SECURE (blocks screenshots and the recent-apps preview).
class SecureWindow {
  static const _ch = MethodChannel('servepos/window');
  static Future<void> set(bool secure) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _ch.invokeMethod('setSecure', {'secure': secure});
    } on MissingPluginException {
      // tests / other platforms
    } on PlatformException {
      // ignore
    }
  }
}

/// Online status = device has a network AND the last server call got through.
class NetStatus extends ChangeNotifier {
  NetStatus({bool listenToDevice = true}) {
    if (listenToDevice) _listen();
  }

  bool _hasNetwork = true;
  bool _serverReachable = true;
  StreamSubscription<List<ConnectivityResult>>? _sub;

  /// Fired when we go from offline to online (outbox flushes then).
  void Function()? onBackOnline;

  bool get online => _hasNetwork && _serverReachable;

  void _listen() {
    try {
      final c = Connectivity();
      c.checkConnectivity().then(_onDevice, onError: (_) {});
      _sub = c.onConnectivityChanged.listen(_onDevice, onError: (_) {});
    } catch (_) {}
  }

  void _onDevice(List<ConnectivityResult> r) {
    final was = online;
    _hasNetwork = r.any((x) => x != ConnectivityResult.none);
    if (_hasNetwork) _serverReachable = true; // give it a chance; next call decides
    _emit(was);
  }

  /// Called by the API client after every request.
  void report(bool reachable) {
    if (reachable == _serverReachable) return;
    final was = online;
    _serverReachable = reachable;
    _emit(was);
  }

  void _emit(bool was) {
    if (was != online) {
      notifyListeners();
      if (online) onBackOnline?.call();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
