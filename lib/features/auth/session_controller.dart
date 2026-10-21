import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/waiter_api.dart';
import '../../core/format.dart';
import '../../core/models/order.dart' show parseServerTime;
import '../../core/models/session.dart';
import '../../core/platform.dart';
import '../../core/server_url.dart';
import '../../core/storage.dart';
import '../settings/app_settings.dart';

enum AuthStage { loading, needServer, needLogin, locked, needProfile, ready }

/// Secure-store keys.
class SecureKeys {
  static const token = 'device_token';
  static const server = 'server_url';
  static const insecureOk = 'server_insecure_ok';
  static const session = 'session_json';
}

/// Owns the sign-in lifecycle:
/// server URL -> password login -> (biometric lock) -> outlet -> ready.
class SessionController extends ChangeNotifier {
  SessionController({
    required this.api,
    required this.secure,
    required this.settings,
    required this.biometric,
    required this.deviceFacts,
    this.allowInsecureLocal = kDebugMode,
    this.httpsOnly = kReleaseMode,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    api.onSessionExpired = _onSessionExpired;
  }

  final WaiterApi api;
  final KeyValueStore secure;
  final AppSettings settings;
  final BiometricGate biometric;
  final DeviceFactsProvider deviceFacts;

  /// Debug builds accept http to local addresses without the extra confirmation.
  final bool allowInsecureLocal;

  /// Release builds: Android blocks cleartext (network_security_config), so
  /// http servers are refused up front with a clear message.
  final bool httpsOnly;
  final DateTime Function() _clock;

  AuthStage stage = AuthStage.loading;
  String? serverUrl;
  SessionInfo? session;
  PosProfile? profile;

  /// Shown once on the login screen (e.g. "Your session ended...").
  String? loginMessage;
  bool busy = false;

  DateTime? _backgroundSince;
  String? _supersededToken;

  /// Hooks for the rest of the app.
  final List<Future<void> Function()> onReady = [];
  final List<Future<void> Function({required bool wipe})> onSignedOut = [];

  WaiterUser? get user => session?.user;
  bool get hasToken => api.token != null;

  void _set(AuthStage s) {
    stage = s;
    notifyListeners();
  }

  Future<void> init() async {
    serverUrl = await secure.read(SecureKeys.server);
    api.baseUrl = serverUrl;
    if (serverUrl == null) return _set(AuthStage.needServer);
    final token = await secure.read(SecureKeys.token);
    if (token == null || token.isEmpty) return _set(AuthStage.needLogin);
    api.token = token;
    final cached = await secure.read(SecureKeys.session);
    if (cached != null) {
      try {
        session = SessionInfo.fromJson(Map<String, dynamic>.from(jsonDecode(cached) as Map));
      } catch (_) {}
    }
    if (settings.biometricEnabled) return _set(AuthStage.locked);
    await _enter();
  }

  // ---------------------------------------------------------------- server

  /// Checks a pasted URL. Throws [ServerUrlException] / returns the normalised URL.
  Future<NormalizedUrl> checkServer(String input, {bool insecureConfirmed = false}) async {
    final n = normalizeServerUrl(input);
    if (n.security == UrlSecurity.insecurePublic) throw ServerUrlException('http_public');
    if (n.security == UrlSecurity.insecureLocal && !allowInsecureLocal) {
      if (httpsOnly) throw ServerUrlException('http_release');
      if (!insecureConfirmed) throw ServerUrlException('http_local');
    }
    final ok = await api.ping(n.url);
    if (!ok) throw ServerUrlException('unreachable');
    return n;
  }

  Future<void> setServer(NormalizedUrl n) async {
    serverUrl = n.url;
    api.baseUrl = n.url;
    await secure.write(SecureKeys.server, n.url);
    await secure.write(SecureKeys.insecureOk, n.security == UrlSecurity.secure ? null : '1');
    _set(AuthStage.needLogin);
  }

  Future<void> changeServer() async {
    await _wipeSession();
    serverUrl = null;
    api.baseUrl = null;
    await secure.delete(SecureKeys.server);
    await secure.delete(SecureKeys.insecureOk);
    _set(AuthStage.needServer);
  }

  // ---------------------------------------------------------------- login

  /// Set after a password login when fingerprint unlock could be offered; the
  /// home shell asks once and clears it.
  bool pendingBiometricOffer = false;

  /// Password login.
  Future<void> login(String usr, String pwd) async {
    busy = true;
    loginMessage = null;
    notifyListeners();
    try {
      final facts = await deviceFacts.facts();
      final r = await api.login(usr: usr.trim(), pwd: pwd, device: facts);
      api.token = r.token;
      await secure.write(SecureKeys.token, r.token);
      await _saveSession(r.session);
      final previousUser = settings.lastUsername;
      await settings.setLastUsername(usr.trim());
      if (previousUser != null && previousUser != usr.trim()) {
        await settings.setBiometric(false);
        await settings.setSelectedProfile(null);
      }
      _revokeSuperseded();
      pendingBiometricOffer = !settings.biometricEnabled && await biometric.isAvailable();
      await _enter();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  /// The old token from a lock-screen "use password instead": revoke it with
  /// itself now that the password proved who this is.
  void _revokeSuperseded() {
    final old = _supersededToken;
    _supersededToken = null;
    if (old == null || old == api.token) return;
    api.logout(tokenOverride: old).catchError((Object _) {});
  }

  Future<void> _saveSession(SessionInfo s) async {
    session = s;
    ServerClock.syncFrom(parseServerTime(s.serverTime));
    await secure.write(SecureKeys.session, jsonEncode(s.toJson()));
  }

  /// Picks the outlet and goes to ready (or the picker).
  Future<void> _enter() async {
    final s = session;
    if (s == null) {
      // Token but no cached profile data: must ask the server.
      try {
        await _saveSession(await api.me());
      } on SessionExpiredException {
        return;
      } on ApiException {
        loginMessage = null;
        return _set(AuthStage.needLogin);
      }
    }
    final profiles = session!.profiles;
    PosProfile? chosen;
    final remembered = settings.selectedProfile;
    if (remembered != null) chosen = profiles.where((p) => p.name == remembered).firstOrNull;
    if (chosen == null && profiles.length == 1) chosen = profiles.first;
    if (chosen == null) {
      return _set(AuthStage.needProfile);
    }
    await chooseProfile(chosen);
  }

  Future<void> chooseProfile(PosProfile p) async {
    profile = p;
    await settings.setSelectedProfile(p.name);
    _set(AuthStage.ready);
    for (final h in onReady) {
      unawaited(h().catchError((Object e) => debugPrint('onReady hook: $e')));
    }
    unawaited(_refreshMe());
  }

  /// Back to the outlet picker (Account > Change outlet).
  void pickAnotherProfile() => _set(AuthStage.needProfile);

  /// Revalidates the token and refreshes profiles in the background. Offline is fine.
  Future<void> _refreshMe() async {
    try {
      final me = await api.me();
      await _saveSession(me);
      final p = profile;
      if (p != null && !me.profiles.any((x) => x.name == p.name)) {
        // Outlet access removed on the server.
        profile = null;
        await settings.setSelectedProfile(null);
        _set(me.profiles.isEmpty ? AuthStage.needLogin : AuthStage.needProfile);
      } else {
        notifyListeners();
      }
    } on ApiException {
      // Offline or server hiccup: keep the cached session.
    }
  }

  // ---------------------------------------------------------------- lock

  Future<bool> unlock(String reason) async {
    final ok = await biometric.authenticate(reason);
    if (ok) await _enter();
    return ok;
  }

  /// Lock screen fallback: forget the stored token and ask for the password.
  Future<void> usePasswordInstead() async {
    _supersededToken = api.token;
    api.token = null;
    await secure.delete(SecureKeys.token);
    loginMessage = null;
    _set(AuthStage.needLogin);
  }

  void markBackground() => _backgroundSince = _clock();

  /// Returns true if it locked.
  bool maybeLockOnResume() {
    final since = _backgroundSince;
    _backgroundSince = null;
    if (since == null || !settings.biometricEnabled || api.token == null) return false;
    if (stage != AuthStage.ready && stage != AuthStage.needProfile) return false;
    if (_clock().difference(since) >= Duration(minutes: settings.idleMinutes)) {
      _set(AuthStage.locked);
      return true;
    }
    return false;
  }

  Future<bool> setBiometric(bool on, String reason) async {
    if (on) {
      if (!await biometric.isAvailable()) return false;
      if (!await biometric.authenticate(reason)) return false;
    }
    await settings.setBiometric(on);
    return true;
  }

  // ---------------------------------------------------------------- sign out

  bool _expiring = false;

  void _onSessionExpired() {
    if (_expiring || api.token == null) return;
    _expiring = true;
    () async {
      try {
        await _wipeSession(keepQueue: true);
        loginMessage = 'session_ended';
        _set(AuthStage.needLogin);
      } finally {
        _expiring = false;
      }
    }();
  }

  Future<void> signOut() async {
    busy = true;
    notifyListeners();
    try {
      if (api.token != null) {
        try {
          await api.logout();
        } on ApiException {
          // Offline: the token is still wiped here; the server expires it.
        }
      }
      await _wipeSession();
      await settings.resetForSignOut();
      loginMessage = null;
      _set(AuthStage.needLogin);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _wipeSession({bool keepQueue = false}) async {
    api.token = null;
    session = null;
    profile = null;
    await secure.delete(SecureKeys.token);
    await secure.delete(SecureKeys.session);
    for (final h in onSignedOut) {
      try {
        await h(wipe: !keepQueue);
      } catch (e) {
        debugPrint('onSignedOut hook: $e');
      }
    }
  }
}
