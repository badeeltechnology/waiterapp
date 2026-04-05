import 'package:flutter/material.dart';
import '../api/erpnext_client.dart';
import '../models/models.dart';

class TableProvider extends ChangeNotifier {
  final _client = ERPNextClient();
  List<TableInfo> _tables = [];
  List<Room> _rooms = [];
  bool _isLoading = false;
  String? _selectedRoom;

  List<TableInfo> get allTables => _tables;
  List<TableInfo> get tables => _selectedRoom == null
    ? _tables
    : _tables.where((t) => t.room == _selectedRoom).toList();
  List<Room> get rooms => _rooms;
  bool get isLoading => _isLoading;
  String? get selectedRoom => _selectedRoom;

  void selectRoom(String? room) {
    _selectedRoom = room;
    notifyListeners();
  }

  Future<void> loadTables() async {
    _isLoading = true;
    notifyListeners();

    try {
      final results = await Future.wait([
        _client.getTables(),
        _client.getRooms(),
      ]);
      _tables = results[0] as List<TableInfo>;
      _rooms = results[1] as List<Room>;
    } catch (e) {
      debugPrint('Failed to load tables: $e');
    }

    _isLoading = false;
    notifyListeners();
  }
}
