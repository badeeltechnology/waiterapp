import 'dart:async';
import 'package:flutter/material.dart';
import '../api/erpnext_client.dart';
import '../models/models.dart';

class OrdersProvider extends ChangeNotifier {
  final _client = ERPNextClient();
  List<WaiterOrder> _orders = [];
  bool _isLoading = false;
  Timer? _pollTimer;

  List<WaiterOrder> get orders => _orders;
  bool get isLoading => _isLoading;

  List<WaiterOrder> get activeOrders =>
    _orders.where((o) => !['Paid', 'Cancelled'].contains(o.status)).toList();

  List<WaiterOrder> get completedOrders =>
    _orders.where((o) => ['Paid', 'Cancelled'].contains(o.status)).toList();

  String _waiterName = '';

  void setWaiterName(String name) {
    _waiterName = name;
  }

  Future<void> loadOrders() async {
    _isLoading = true;
    notifyListeners();

    try {
      _orders = await _client.getMyOrders(_waiterName);
    } catch (e) {
      debugPrint('Failed to load orders: $e');
    }

    _isLoading = false;
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

  // Start polling for status updates
  void startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => loadOrders());
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
