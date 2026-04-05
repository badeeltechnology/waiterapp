import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../api/erpnext_client.dart';
import '../models/models.dart';
import '../utils/local_db.dart';

class CartProvider extends ChangeNotifier {
  final _client = ERPNextClient();
  final List<CartItem> _items = [];
  String _orderType = 'Dine In';
  String? _tableName;
  String? _room;
  int _guests = 1;
  String? _notes;
  bool _isSubmitting = false;
  String? _error;
  int _queuedCount = 0;
  bool _isOnline = true;
  StreamSubscription? _connectivitySub;

  List<CartItem> get items => _items;
  String get orderType => _orderType;
  String? get tableName => _tableName;
  String? get room => _room;
  int get guests => _guests;
  String? get notes => _notes;
  bool get isSubmitting => _isSubmitting;
  String? get error => _error;
  int get itemCount => _items.fold(0, (sum, i) => sum + i.qty);
  double get total => _items.fold(0, (sum, i) => sum + i.amount);
  int get queuedCount => _queuedCount;
  bool get isOnline => _isOnline;

  CartProvider() {
    _initConnectivity();
    _loadQueuedCount();
  }

  void _initConnectivity() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final wasOffline = !_isOnline;
      _isOnline = results.any((r) => r != ConnectivityResult.none);
      notifyListeners();

      // Was offline, now online — try to sync queued orders
      if (wasOffline && _isOnline) {
        syncQueuedOrders();
      }
    });
  }

  Future<void> _loadQueuedCount() async {
    _queuedCount = await LocalDb.getQueuedCount();
    notifyListeners();
  }

  void setOrderType(String type) {
    _orderType = type;
    if (type != 'Dine In') {
      _tableName = null;
      _room = null;
    }
    notifyListeners();
  }

  void setTable(String? table, String? room) {
    _tableName = table;
    _room = room;
    notifyListeners();
  }

  void setGuests(int count) {
    _guests = count;
    notifyListeners();
  }

  void setNotes(String? notes) {
    _notes = notes;
    notifyListeners();
  }

  void addItem(CartItem item) {
    final existing = _items.indexWhere((i) =>
      i.itemCode == item.itemCode &&
      jsonEncode(i.modifiers.map((m) => m.name).toList()) ==
      jsonEncode(item.modifiers.map((m) => m.name).toList())
    );

    if (existing >= 0) {
      _items[existing].qty += item.qty;
    } else {
      _items.add(item);
    }
    notifyListeners();
  }

  void updateQty(int index, int qty) {
    if (qty <= 0) {
      _items.removeAt(index);
    } else {
      _items[index].qty = qty;
    }
    notifyListeners();
  }

  void removeItem(int index) {
    _items.removeAt(index);
    notifyListeners();
  }

  void updateSpecialInstructions(int index, String? instructions) {
    _items[index].specialInstructions = instructions;
    notifyListeners();
  }

  void clearCart() {
    _items.clear();
    _tableName = null;
    _room = null;
    _guests = 1;
    _notes = null;
    _orderType = 'Dine In';
    _error = null;
    notifyListeners();
  }

  Future<Map<String, dynamic>?> submitOrder(String waiterName) async {
    if (_items.isEmpty) return null;

    _isSubmitting = true;
    _error = null;
    notifyListeners();

    final orderData = {
      'order_type': _orderType,
      'table': _tableName,
      'room': _room,
      'guests': _guests,
      'notes': _notes,
      'items': _items.map((i) => i.toOrderItem()).toList(),
    };

    try {
      final order = await _client.createWaiterOrder(waiterName, orderData);
      clearCart();
      await _loadQueuedCount();
      return order;
    } catch (e) {
      // Network failure — queue order locally for later sync
      debugPrint('Order submit failed, queuing locally: $e');
      await LocalDb.queueOrder(waiterName, orderData);
      await _loadQueuedCount();
      clearCart();
      _error = null; // Don't show error — order is queued
      notifyListeners();
      return {'queued': true, 'message': 'Order saved offline. Will sync when online.'};
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  /// Sync all queued orders to ERPNext
  Future<int> syncQueuedOrders() async {
    final queued = await LocalDb.getQueuedOrders();
    int synced = 0;

    for (final row in queued) {
      try {
        final orderData = jsonDecode(row['order_data'] as String) as Map<String, dynamic>;
        final waiterName = row['waiter_name'] as String;
        await _client.createWaiterOrder(waiterName, orderData);
        await LocalDb.markSynced(row['id'] as int);
        synced++;
      } catch (e) {
        await LocalDb.markFailed(row['id'] as int, e.toString());
      }
    }

    await _loadQueuedCount();
    await LocalDb.cleanupSynced();
    return synced;
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }
}
