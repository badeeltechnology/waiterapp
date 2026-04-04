import 'package:flutter/material.dart';
import '../api/erpnext_client.dart';
import '../models/models.dart';

class MenuProvider extends ChangeNotifier {
  final _client = ERPNextClient();
  List<ItemGroup> _groups = [];
  List<MenuItem> _items = [];
  bool _isLoading = false;
  String? _selectedGroup;

  List<ItemGroup> get groups => _groups;
  List<MenuItem> get allItems => _items;
  bool get isLoading => _isLoading;
  String? get selectedGroup => _selectedGroup;

  List<MenuItem> get filteredItems {
    if (_selectedGroup == null) return _items;
    return _items.where((i) => i.itemGroup == _selectedGroup).toList();
  }

  void selectGroup(String? group) {
    _selectedGroup = group;
    notifyListeners();
  }

  Future<void> loadMenu() async {
    _isLoading = true;
    notifyListeners();

    try {
      final results = await Future.wait([
        _client.getItemGroups(),
        _client.getItems(),
      ]);
      _groups = results[0] as List<ItemGroup>;
      _items = results[1] as List<MenuItem>;
    } catch (e) {
      debugPrint('Failed to load menu: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<List<ModifierGroup>> getItemModifiers(String itemCode) async {
    return _client.getItemModifiers(itemCode);
  }

  List<MenuItem> search(String query) {
    final q = query.toLowerCase();
    return _items.where((i) =>
      i.itemName.toLowerCase().contains(q) ||
      (i.itemNameAr?.contains(q) ?? false) ||
      i.itemCode.toLowerCase().contains(q)
    ).toList();
  }
}
