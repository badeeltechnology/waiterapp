import 'dart:convert';
import 'package:flutter/material.dart';
import '../api/erpnext_client.dart';
import '../models/models.dart';

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
    // Check if same item with same modifiers exists
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

    try {
      final orderData = {
        'order_type': _orderType,
        'table': _tableName,
        'room': _room,
        'guests': _guests,
        'notes': _notes,
        'items': _items.map((i) => i.toOrderItem()).toList(),
      };

      final order = await _client.createWaiterOrder(waiterName, orderData);
      clearCart();
      return order;
    } catch (e) {
      _error = 'Failed to submit order: $e';
      notifyListeners();
      return null;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }
}
