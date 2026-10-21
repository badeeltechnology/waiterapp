import 'package:flutter/foundation.dart';

import '../../core/platform.dart';
import '../../core/storage.dart';

/// Per-phone preferences (not secrets).
class AppSettings extends ChangeNotifier {
  AppSettings(this._prefs);
  final KeyValueStore _prefs;

  static const idleChoices = [1, 2, 5, 10, 15, 30];

  String language = 'en';
  int idleMinutes = 5;
  bool blockScreenshots = false;
  bool biometricEnabled = false;
  String? lastUsername;
  String? selectedProfile;

  Future<void> load() async {
    language = await _prefs.read('language') ?? 'en';
    idleMinutes = int.tryParse(await _prefs.read('idle_minutes') ?? '') ?? 5;
    blockScreenshots = await _prefs.read('block_screenshots') == '1';
    biometricEnabled = await _prefs.read('biometric') == '1';
    lastUsername = await _prefs.read('last_username');
    selectedProfile = await _prefs.read('pos_profile');
    await SecureWindow.set(blockScreenshots);
    notifyListeners();
  }

  Future<void> setLanguage(String v) async {
    language = v == 'ar' ? 'ar' : 'en';
    await _prefs.write('language', language);
    notifyListeners();
  }

  Future<void> setIdleMinutes(int v) async {
    idleMinutes = v;
    await _prefs.write('idle_minutes', '$v');
    notifyListeners();
  }

  Future<void> setBlockScreenshots(bool v) async {
    blockScreenshots = v;
    await _prefs.write('block_screenshots', v ? '1' : '0');
    await SecureWindow.set(v);
    notifyListeners();
  }

  Future<void> setBiometric(bool v) async {
    biometricEnabled = v;
    await _prefs.write('biometric', v ? '1' : '0');
    notifyListeners();
  }

  Future<void> setLastUsername(String? v) async {
    lastUsername = v;
    await _prefs.write('last_username', v);
  }

  Future<void> setSelectedProfile(String? v) async {
    selectedProfile = v;
    await _prefs.write('pos_profile', v);
    notifyListeners();
  }

  /// Sign-out: forget who used the phone; keep language and screen settings.
  Future<void> resetForSignOut() async {
    await setBiometric(false);
    await setSelectedProfile(null);
  }
}
