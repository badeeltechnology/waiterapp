import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/alerts.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/waiter_api.dart';
import '../../core/models/order.dart';

class CallsController extends ChangeNotifier {
  CallsController({required this.api, required this.alerts});
  final WaiterApi api;
  final Alerts alerts;

  String? profile;
  String? myWaiter;
  List<GuestCall> calls = const [];
  bool loading = false;
  ApiException? error;
  final Set<String> busy = {};
  final Set<String> _known = {};
  Timer? _timer;

  int get waitingCount => calls.where((c) => !c.isAccepted).length;

  void open(String posProfile, String waiter) {
    profile = posProfile;
    myWaiter = waiter;
    refresh();
    startPolling();
  }

  /// Safety net when push is late or missing. Push triggers refresh() too.
  void startPolling({Duration every = const Duration(seconds: 10)}) {
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => refresh());
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> refresh() async {
    final p = profile;
    if (p == null || loading) return;
    loading = true;
    try {
      final list = await api.activeCalls(p);
      final firstLoad = _known.isEmpty && calls.isEmpty;
      for (final c in list) {
        if (!_known.contains(c.name) && !c.isAccepted && !firstLoad) {
          // A call that polling found first: alert loudly (deduped with push).
          alerts.showCall(id: c.name, title: 'Table ${c.table ?? '?'} is calling', body: c.guestNote ?? c.room ?? '');
        }
        _known.add(c.name);
      }
      // Calls that disappeared or were taken by someone else: stop ringing.
      for (final old in calls) {
        final now = list.where((c) => c.name == old.name).firstOrNull;
        if (now == null || (now.isAccepted && now.acceptedBy != myWaiter)) alerts.cancel(old.name);
      }
      calls = list;
      error = null;
    } on ApiException catch (e) {
      error = e;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Returns null on success, or the name of the waiter who already took it.
  Future<String?> accept(String name) async {
    busy.add(name);
    notifyListeners();
    try {
      final r = await api.acceptCall(name);
      await alerts.cancel(name);
      await refresh();
      return r.ok ? null : (r.acceptedBy ?? '?');
    } finally {
      busy.remove(name);
      notifyListeners();
    }
  }

  Future<void> attended(String name) async {
    busy.add(name);
    notifyListeners();
    try {
      await api.attendCall(name);
      await alerts.cancel(name);
      calls = calls.where((c) => c.name != name).toList();
      await refresh();
    } finally {
      busy.remove(name);
      notifyListeners();
    }
  }

  void clear() {
    stopPolling();
    profile = null;
    calls = const [];
    _known.clear();
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}
