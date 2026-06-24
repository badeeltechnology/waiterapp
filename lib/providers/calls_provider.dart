import 'dart:async';
import 'package:flutter/material.dart';
import '../api/erpnext_client.dart';
import '../models/models.dart';

class CallsProvider extends ChangeNotifier {
  final _client = ERPNextClient();
  List<WaiterCall> _pendingCalls = [];
  List<WaiterCall> _myCalls = [];
  List<WaiterCall> _history = [];
  bool _isLoading = false;
  String? _error;
  Timer? _pollTimer;
  String _waiterName = '';

  // Incoming call alert
  WaiterCall? _incomingCall;

  List<WaiterCall> get pendingCalls => _pendingCalls;
  List<WaiterCall> get myCalls => _myCalls;
  List<WaiterCall> get history => _history;
  bool get isLoading => _isLoading;
  String? get error => _error;
  WaiterCall? get incomingCall => _incomingCall;

  int get pendingCount => _pendingCalls.length;
  int get activeCount => _myCalls.length;
  bool get hasIncoming => _incomingCall != null;

  void setWaiterName(String name) {
    _waiterName = name;
  }

  /// Called when FCM push arrives (foreground or tap from background)
  void onNewCall(WaiterCall call) {
    // Add to pending if not already there
    if (!_pendingCalls.any((c) => c.name == call.name)) {
      _pendingCalls.insert(0, call);
    }
    // Show as incoming alert
    _incomingCall = call;
    notifyListeners();
  }

  /// Called when FCM says a call was accepted by someone else
  void onCallAccepted(String callName, String acceptedBy) {
    _pendingCalls.removeWhere((c) => c.name == callName);
    if (_incomingCall?.name == callName) {
      _incomingCall = null;
    }
    notifyListeners();
  }

  /// Dismiss the incoming call alert without accepting
  void dismissIncoming() {
    _incomingCall = null;
    notifyListeners();
  }

  /// Accept a call — first waiter wins
  Future<bool> acceptCall(String callName) async {
    if (_waiterName.isEmpty) return false;
    try {
      final result = await _client.acceptCall(callName, _waiterName);
      if (result['success'] == true) {
        // Move from pending to my calls
        final call = _pendingCalls.firstWhere(
          (c) => c.name == callName,
          orElse: () => WaiterCall(
            name: callName,
            table: result['table'] ?? '',
            tableName: result['table_name'] ?? '',
            posProfile: '',
            restaurantName: '',
            status: 'Accepted',
            guestName: result['guest_name'],
          ),
        );
        _pendingCalls.removeWhere((c) => c.name == callName);
        _myCalls.insert(0, WaiterCall(
          name: call.name,
          table: call.table,
          tableName: result['table_name'] ?? call.tableName,
          posProfile: call.posProfile,
          restaurantName: call.restaurantName,
          status: 'Accepted',
          callTime: call.callTime,
          guestName: result['guest_name'] ?? call.guestName,
          notes: call.notes,
          roomName: call.roomName,
        ));
        _incomingCall = null;
        notifyListeners();
        return true;
      } else {
        // Someone else accepted
        _pendingCalls.removeWhere((c) => c.name == callName);
        _incomingCall = null;
        notifyListeners();
        return false;
      }
    } catch (e) {
      debugPrint('Accept call failed: $e');
      return false;
    }
  }

  /// Mark a call as attended
  Future<bool> markAttended(String callName) async {
    if (_waiterName.isEmpty) return false;
    try {
      final result = await _client.markCallAttended(callName, _waiterName);
      if (result['success'] == true) {
        _myCalls.removeWhere((c) => c.name == callName);
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Mark attended failed: $e');
      return false;
    }
  }

  /// Load all active calls from server
  Future<void> loadCalls() async {
    if (_waiterName.isEmpty) return;
    _isLoading = _pendingCalls.isEmpty && _myCalls.isEmpty;
    _error = null;

    try {
      // Fetch pending calls (for all waiters of this profile)
      final activeCalls = await _client.getActiveCalls();
      final previousPending = Set.of(_pendingCalls.map((c) => c.name));

      _pendingCalls = activeCalls
          .where((c) => c['status'] == 'Pending')
          .map((c) => WaiterCall.fromJson(c))
          .toList();

      // Detect new calls for alert
      for (final call in _pendingCalls) {
        if (!previousPending.contains(call.name) && _incomingCall == null) {
          _incomingCall = call;
        }
      }

      // Fetch my accepted calls
      final myActive = await _client.getMyActiveCalls(_waiterName);
      _myCalls = myActive.map((c) => WaiterCall.fromJson(c)).toList();
    } catch (e) {
      _error = 'Failed to load calls: $e';
      debugPrint(_error);
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Load call history
  Future<void> loadHistory() async {
    try {
      final data = await _client.getCallHistory(waiterName: _waiterName, days: 1);
      _history = data.map((c) => WaiterCall.fromJson(c)).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load call history: $e');
    }
  }

  /// Start polling for calls every 5 seconds
  void startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => loadCalls());
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}
