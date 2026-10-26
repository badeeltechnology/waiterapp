import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/alerts.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/waiter_api.dart';
import '../../core/models/order.dart';

/// Today's orders. A failed refresh keeps the last good list (UX review: a
/// network blip emptied the list).
class OrdersController extends ChangeNotifier {
  OrdersController({required this.api, required this.alerts});
  final WaiterApi api;
  final Alerts alerts;

  String? profile;
  bool showAll = false;
  List<Order> orders = const [];
  bool loading = false;
  ApiException? error;
  DateTime? updatedAt;
  OrderStatus? filter;

  /// Called when an order of this list changes to Accepted, Ready or Rejected
  /// (found by polling or push).
  void Function(Order order, OrderStatus from)? onStatusChange;
  Timer? _timer;
  Duration _every = const Duration(seconds: 15);

  /// Safety net for status changes when push is late or off (this build has no
  /// push). Push triggers refresh() too.
  void startPolling({Duration every = const Duration(seconds: 15)}) {
    _every = every;
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => refresh());
  }

  void resumePolling() => startPolling(every: _every);

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  /// Orders that turned Ready since the waiter last looked.
  final Set<String> readyUnseen = {};
  final Map<String, OrderStatus> _lastStatus = {};

  List<Order> get visible => filter == null ? orders : orders.where((o) => o.status == filter).toList();

  void open(String posProfile) {
    if (profile != posProfile) {
      profile = posProfile;
      orders = const [];
      _lastStatus.clear();
      readyUnseen.clear();
    }
    refresh();
  }

  void setShowAll(bool v) {
    if (showAll == v) return;
    showAll = v;
    orders = const [];
    filter = null;
    notifyListeners();
    refresh();
  }

  void setFilter(OrderStatus? s) {
    filter = s;
    notifyListeners();
  }

  Future<void> refresh() async {
    final p = profile;
    if (p == null || loading) return;
    loading = true;
    notifyListeners();
    try {
      final list = await api.myOrders(p, all: showAll);
      _detectReady(list);
      orders = list;
      updatedAt = DateTime.now();
      error = null;
    } on ApiException catch (e) {
      error = e;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void _detectReady(List<Order> list) {
    final first = _lastStatus.isEmpty;
    for (final o in list) {
      final prev = _lastStatus[o.name];
      if (o.status == OrderStatus.ready && prev != OrderStatus.ready) {
        readyUnseen.add(o.name);
        // Push normally announces this; polling is the safety net (deduped).
        if (!first) {
          alerts.showOrder(id: 'order_ready:${o.name}', title: o.table == null ? '${o.name} is ready' : 'Table ${o.table} is ready', body: o.name);
        }
      }
      if (o.status != OrderStatus.ready) readyUnseen.remove(o.name);
      if (!first &&
          prev != null &&
          prev != o.status &&
          (o.status == OrderStatus.accepted || o.status == OrderStatus.ready || o.status == OrderStatus.rejected)) {
        onStatusChange?.call(o, prev);
      }
      _lastStatus[o.name] = o.status;
    }
  }

  void markReadySeen(String name) {
    if (readyUnseen.remove(name)) notifyListeners();
  }

  /// Puts a confirmed order at the top straight away.
  void upsert(Order o) {
    final list = [...orders]..removeWhere((x) => x.name == o.name);
    orders = [o, ...list];
    _lastStatus[o.name] = o.status;
    notifyListeners();
  }

  Future<Order> load(String name) async {
    final o = await api.order(name);
    if (orders.any((x) => x.name == name)) {
      orders = [for (final x in orders) x.name == name ? o : x];
      notifyListeners();
    }
    return o;
  }

  Future<void> cancel(String name, String reason) async {
    await api.cancelOrder(name, reason);
    await refresh();
  }

  void clear() {
    stopPolling();
    profile = null;
    orders = const [];
    _lastStatus.clear();
    readyUnseen.clear();
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}
