import 'dart:async';
import 'package:flutter/material.dart';
import '../api/erpnext_client.dart';
import '../models/models.dart';

class OrdersProvider extends ChangeNotifier {
  final _client = ERPNextClient();
  List<WaiterOrder> _orders = [];
  bool _isLoading = false;
  Timer? _pollTimer;

  // Ready to serve notifications
  final Set<String> _readyNotifiedOrders = {};
  List<WaiterOrder> _newlyReadyOrders = [];

  List<WaiterOrder> get orders => _orders;
  bool get isLoading => _isLoading;

  List<WaiterOrder> get activeOrders =>
    _orders.where((o) => !['Paid', 'Cancelled'].contains(o.status)).toList();

  List<WaiterOrder> get completedOrders =>
    _orders.where((o) => ['Paid', 'Cancelled'].contains(o.status)).toList();

  /// Orders that just became "Ready" — for alert display
  List<WaiterOrder> get newlyReadyOrders => _newlyReadyOrders;

  /// Whether there are unacknowledged ready orders
  bool get hasReadyAlert => _newlyReadyOrders.isNotEmpty;

  /// All orders currently in "Ready" status
  List<WaiterOrder> get readyOrders =>
    _orders.where((o) => o.status == 'Ready').toList();

  String _waiterName = '';

  void setWaiterName(String name) {
    _waiterName = name;
  }

  Future<void> loadOrders() async {
    _isLoading = true;
    notifyListeners();

    try {
      final previousOrders = Map.fromEntries(
        _orders.map((o) => MapEntry(o.name, o.status))
      );

      _orders = await _client.getMyOrders(_waiterName);

      // Detect orders that just became "Ready"
      for (final order in _orders) {
        if (order.status == 'Ready' &&
            previousOrders[order.name] != 'Ready' &&
            !_readyNotifiedOrders.contains(order.name)) {
          _newlyReadyOrders.add(order);
          _readyNotifiedOrders.add(order.name);
        }
      }

      // Clean up dismissed orders that are no longer Ready
      _newlyReadyOrders.removeWhere(
        (o) => !_orders.any((curr) => curr.name == o.name && curr.status == 'Ready')
      );
    } catch (e, stack) {
      debugPrint('Failed to load orders: $e');
      debugPrint('Stack: $stack');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Acknowledge a ready order notification (dismiss the alert)
  void acknowledgeReadyOrder(String orderName) {
    _newlyReadyOrders.removeWhere((o) => o.name == orderName);
    notifyListeners();
  }

  /// Dismiss all ready alerts
  void acknowledgeAllReady() {
    _newlyReadyOrders.clear();
    notifyListeners();
  }

  Future<WaiterOrder?> getOrder(String name) async {
    try {
      final doc = await _client.getDoc('ServePOS Waiter Order', name);
      return WaiterOrder.fromJson(doc);
    } catch (e) {
      debugPrint('Failed to get order: $e');
      return null;
    }
  }

  Future<void> cancelOrder(String name) async {
    await _client.updateOrderStatus(name, 'Cancelled');
    await loadOrders();
  }

  // Start polling — every 10 seconds
  void startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => loadOrders());
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
