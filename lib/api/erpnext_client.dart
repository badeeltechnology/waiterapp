import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class ERPNextClient {
  String _baseUrl = '';
  String _apiKey = '';
  String _apiSecret = '';
  String _posProfile = '';

  static final ERPNextClient _instance = ERPNextClient._internal();
  factory ERPNextClient() => _instance;
  ERPNextClient._internal();

  String get baseUrl => _baseUrl;
  String get posProfile => _posProfile;
  bool get isConfigured => _baseUrl.isNotEmpty && _apiKey.isNotEmpty;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('erpnext_url') ?? '';
    _apiKey = prefs.getString('api_key') ?? '';
    _apiSecret = prefs.getString('api_secret') ?? '';
    _posProfile = prefs.getString('pos_profile') ?? '';
  }

  Future<void> configure(String url, String apiKey, String apiSecret, {String? posProfile}) async {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    _apiKey = apiKey;
    _apiSecret = apiSecret;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('erpnext_url', _baseUrl);
    await prefs.setString('api_key', _apiKey);
    await prefs.setString('api_secret', _apiSecret);
    if (posProfile != null) {
      _posProfile = posProfile;
      await prefs.setString('pos_profile', posProfile);
    }
  }

  Future<void> setPosProfile(String posProfile) async {
    _posProfile = posProfile;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pos_profile', posProfile);
  }

  String _requireProfile() {
    if (_posProfile.isEmpty) {
      throw Exception('pos_profile is required. Configure the device POS Profile first.');
    }
    return _posProfile;
  }

  Future<void> clearConfig() async {
    _baseUrl = '';
    _apiKey = '';
    _apiSecret = '';
    _posProfile = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('erpnext_url');
    await prefs.remove('api_key');
    await prefs.remove('api_secret');
    await prefs.remove('pos_profile');
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'Authorization': 'token $_apiKey:$_apiSecret',
  };

  // ==================== Test Connection ====================

  Future<bool> testConnection() async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/api/method/frappe.auth.get_logged_user'),
        headers: _headers,
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ==================== Generic API ====================

  Future<List<dynamic>> getList(String doctype, {
    List<String>? fields,
    List<dynamic>? filters,
    int limit = 0,
    String? orderBy,
  }) async {
    final params = <String, String>{};
    if (fields != null) params['fields'] = jsonEncode(fields);
    if (filters != null) params['filters'] = jsonEncode(filters);
    // Frappe defaults to 20 records if limit_page_length is not set.
    // Pass a large number to fetch all records.
    params['limit_page_length'] = limit > 0 ? '$limit' : '9999';
    if (orderBy != null) params['order_by'] = orderBy;

    final uri = Uri.parse('$_baseUrl/api/resource/$doctype').replace(queryParameters: params);
    final res = await http.get(uri, headers: _headers);
    if (res.statusCode != 200) throw Exception('Failed to fetch $doctype: ${res.statusCode}');
    final data = jsonDecode(res.body);
    return data['data'] ?? [];
  }

  Future<Map<String, dynamic>> getDoc(String doctype, String name) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/api/resource/$doctype/${Uri.encodeComponent(name)}'),
      headers: _headers,
    );
    if (res.statusCode != 200) throw Exception('Failed to fetch $doctype/$name');
    final data = jsonDecode(res.body);
    return data['data'] ?? {};
  }

  Future<dynamic> callMethod(String method, {Map<String, dynamic>? args}) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/api/method/$method'),
      headers: _headers,
      body: args != null ? jsonEncode(args) : null,
    );
    if (res.statusCode != 200) {
      debugPrint('API $method failed: ${res.statusCode} — ${res.body}');
      throw Exception('Method $method failed: ${res.statusCode}');
    }
    final data = jsonDecode(res.body);
    return data['message'];
  }

  // ==================== Waiter Auth ====================

  Future<List<Map<String, dynamic>>> getWaiters() async {
    // Centralized registry — filtered by POS Profile server-side.
    final pos_profile = _requireProfile();
    final result = await callMethod(
      'servepos.api.registry.get_waiters',
      args: {'pos_profile': pos_profile},
    );
    if (result is List) return result.cast<Map<String, dynamic>>();
    return [];
  }

  Future<Map<String, dynamic>> verifyWaiterPin(String waiterName, String pin) async {
    final result = await callMethod('servepos.api.waiter.verify_waiter_pin', args: {
      'waiter_name': waiterName,
      'pin': pin,
    });
    return result is Map<String, dynamic> ? result : {'success': false, 'error': 'Invalid response'};
  }

  // ==================== Menu ====================
  // All list APIs go through servepos.api.registry — the single source of
  // truth for POS Profile filtering. Do NOT use getList() here.

  Future<List<ItemGroup>> getItemGroups() async {
    final pos_profile = _requireProfile();
    final result = await callMethod(
      'servepos.api.registry.get_item_groups',
      args: {'pos_profile': pos_profile},
    );
    if (result is List) {
      return result.map((g) => ItemGroup.fromJson(g as Map<String, dynamic>)).toList();
    }
    return [];
  }

  Future<List<MenuItem>> getItems() async {
    final pos_profile = _requireProfile();
    final result = await callMethod(
      'servepos.api.registry.get_items',
      args: {'pos_profile': pos_profile},
    );
    if (result is List) {
      return result.map((i) => MenuItem.fromJson(i as Map<String, dynamic>)).toList();
    }
    return [];
  }

  Future<List<ModifierGroup>> getItemModifiers(String itemCode) async {
    try {
      final result = await callMethod('servepos.api.pos_session.get_item_modifiers', args: {'item_code': itemCode});
      if (result is List) {
        return result.map((g) => ModifierGroup.fromJson(g)).toList();
      }
    } catch (_) {}
    return [];
  }

  // ==================== Tables & Rooms ====================

  Future<List<TableInfo>> getTables() async {
    final pos_profile = _requireProfile();
    final result = await callMethod(
      'servepos.api.registry.get_tables',
      args: {'pos_profile': pos_profile},
    );
    if (result is List) {
      return result
          .map((t) => TableInfo.fromJson(t as Map<String, dynamic>))
          .where((t) => t.isActive)
          .toList();
    }
    return [];
  }

  Future<List<Room>> getRooms() async {
    final pos_profile = _requireProfile();
    final result = await callMethod(
      'servepos.api.registry.get_rooms',
      args: {'pos_profile': pos_profile},
    );
    if (result is List) {
      return result
          .map((r) => Room.fromJson(r as Map<String, dynamic>))
          .where((r) => r.isActive)
          .toList();
    }
    return [];
  }

  // ==================== Waiter Orders ====================

  Future<Map<String, dynamic>> createWaiterOrder(String waiterName, Map<String, dynamic> orderData) async {
    final result = await callMethod('servepos.api.waiter.create_order', args: {
      'waiter_name': waiterName,
      'order_type': orderData['order_type'],
      'table': orderData['table'],
      'room': orderData['room'],
      'guests': orderData['guests'],
      'notes': orderData['notes'],
      'items': jsonEncode(orderData['items']),
    });
    return result is Map<String, dynamic> ? result : {};
  }

  Future<List<WaiterOrder>> getMyOrders(String waiterName) async {
    debugPrint('getMyOrders called for waiter: "$waiterName"');

    // Try the dedicated API
    try {
      final result = await callMethod('servepos.api.waiter.get_my_orders', args: {'waiter_name': waiterName});
      if (result is List) {
        debugPrint('get_my_orders returned ${result.length} orders');
        return result.map((o) => WaiterOrder.fromJson(o as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('get_my_orders API failed: $e');
    }

    return [];
  }

  Future<void> updateOrderStatus(String orderName, String status) async {
    await callMethod('servepos.api.waiter.update_order_status', args: {
      'order_name': orderName,
      'status': status,
    });
  }
}
