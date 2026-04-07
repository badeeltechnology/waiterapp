import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/erpnext_client.dart';

class AuthProvider extends ChangeNotifier {
  final _client = ERPNextClient();
  bool _isConfigured = false;
  bool _isLoggedIn = false;
  bool _isLoading = true;
  String _waiterName = '';
  String? _error;
  List<Map<String, dynamic>> _waiters = [];

  bool get isConfigured => _isConfigured;
  bool get isLoggedIn => _isLoggedIn;
  bool get isLoading => _isLoading;
  String get waiterName => _waiterName;
  String? get error => _error;
  List<Map<String, dynamic>> get waiters => _waiters;
  String get serverUrl => _client.baseUrl;
  String get posProfile => _client.posProfile;
  bool get hasPosProfile => _client.posProfile.isNotEmpty;

  Future<void> init() async {
    await _client.init();
    _isConfigured = _client.isConfigured && _client.posProfile.isNotEmpty;

    if (_isConfigured) {
      // Check if waiter was previously logged in
      final prefs = await SharedPreferences.getInstance();
      _waiterName = prefs.getString('waiter_name') ?? '';
      if (_waiterName.isNotEmpty) {
        _isLoggedIn = true;
      }
      // Fetch waiter list (centralized, filtered by POS profile)
      try {
        _waiters = await _client.getWaiters();
      } catch (_) {}
    }

    _isLoading = false;
    notifyListeners();
  }

  // Configure from QR code: "url|api_key|api_secret|pos_profile"
  // pos_profile is required — each device must belong to a profile.
  Future<bool> configureFromQR(String qrData) async {
    _error = null;
    _isLoading = true;
    notifyListeners();

    try {
      final parts = qrData.split('|');
      if (parts.length >= 4) {
        await _client.configure(
          parts[0],
          parts[1],
          parts[2],
          posProfile: parts[3],
        );
        final ok = await _client.testConnection();
        if (ok) {
          _isConfigured = true;
          _waiters = await _client.getWaiters();
          _isLoading = false;
          notifyListeners();
          return true;
        } else {
          _error = 'Connection failed. Check QR code.';
          await _client.clearConfig();
        }
      } else if (parts.length == 3) {
        _error = 'QR missing POS Profile. Regenerate QR to include profile.';
      } else {
        _error = 'Invalid QR code format';
      }
    } catch (e) {
      _error = 'Setup failed: $e';
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  // Manual profile override (used by settings screen).
  Future<void> setPosProfile(String posProfile) async {
    await _client.setPosProfile(posProfile);
    _isConfigured = _client.isConfigured && _client.posProfile.isNotEmpty;
    try {
      _waiters = await _client.getWaiters();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> loadWaiters() async {
    try {
      _waiters = await _client.getWaiters();
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> loginWithPin(String waiterName, String pin) async {
    _error = null;
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _client.verifyWaiterPin(waiterName, pin);
      if (result['success'] == true) {
        _waiterName = waiterName;
        _isLoggedIn = true;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('waiter_name', waiterName);
      } else {
        _error = result['error'] ?? 'Invalid PIN';
      }
    } catch (e) {
      _error = 'Login failed: $e';
    }

    _isLoading = false;
    notifyListeners();
    return _isLoggedIn;
  }

  Future<void> logout() async {
    _isLoggedIn = false;
    _waiterName = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('waiter_name');
    notifyListeners();
  }

  Future<void> resetConfig() async {
    await _client.clearConfig();
    _isConfigured = false;
    _isLoggedIn = false;
    _waiterName = '';
    _waiters = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('waiter_name');
    notifyListeners();
  }
}
