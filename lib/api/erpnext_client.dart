import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';

class ERPNextClient {
  String _baseUrl = '';
  String _apiKey = '';
  String _apiSecret = '';

  static final ERPNextClient _instance = ERPNextClient._internal();
  factory ERPNextClient() => _instance;
  ERPNextClient._internal();

  String get baseUrl => _baseUrl;
  bool get isConfigured => _baseUrl.isNotEmpty && _apiKey.isNotEmpty;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('erpnext_url') ?? '';
    _apiKey = prefs.getString('api_key') ?? '';
    _apiSecret = prefs.getString('api_secret') ?? '';
  }

  Future<void> configure(String url, String apiKey, String apiSecret) async {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    _apiKey = apiKey;
    _apiSecret = apiSecret;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('erpnext_url', _baseUrl);
    await prefs.setString('api_key', _apiKey);
    await prefs.setString('api_secret', _apiSecret);
  }

  Future<void> clearConfig() async {
    _baseUrl = '';
    _apiKey = '';
    _apiSecret = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('erpnext_url');
    await prefs.remove('api_key');
    await prefs.remove('api_secret');
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
    final result = await callMethod('servepos.api.waiter.get_waiters');
    if (result is List) {
      return result.cast<Map<String, dynamic>>();
    }
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

  Future<List<ItemGroup>> getItemGroups() async {
    final list = await getList('Item Group', fields: ['name', 'parent_item_group', 'image']);
    return list.map((g) => ItemGroup.fromJson(g)).toList();
  }

  Future<List<MenuItem>> getItems() async {
    final fields = [
      'name', 'item_name', 'description', 'item_group', 'standard_rate',
      'stock_uom', 'image', 'has_variants', 'variant_of',
      'servepos_item_name_ar', 'servepos_is_available'
    ];
    try {
      final list = await getList('Item', fields: fields, filters: [['disabled', '=', 0], ['servepos_is_available', '=', 1]]);
      return list.map((i) => MenuItem.fromJson(i)).toList();
    } catch (_) {
      final list = await getList('Item', fields: ['name', 'item_name', 'description', 'item_group', 'standard_rate', 'image', 'has_variants'], filters: [['disabled', '=', 0]]);
      return list.map((i) => MenuItem.fromJson(i)).toList();
    }
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
    final list = await getList('ServePOS Table', fields: ['name', 'table_name', 'room', 'capacity', 'status', 'is_active']);
    return list.map((t) => TableInfo.fromJson(t)).where((t) => t.isActive).toList();
  }

  Future<List<Room>> getRooms() async {
    final list = await getList('ServePOS Room', fields: ['name', 'room_name', 'is_active']);
    return list.map((r) => Room.fromJson(r)).where((r) => r.isActive).toList();
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
    // Try the dedicated API first
    try {
      final result = await callMethod('servepos.api.waiter.get_my_orders', args: {'waiter_name': waiterName});
      debugPrint('getMyOrders response type: ${result.runtimeType}, waiter: $waiterName');
      if (result is List && result.isNotEmpty) {
        return result.map((o) => WaiterOrder.fromJson(o as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('getMyOrders API error: $e');
    }

    // Fallback: fetch directly from doctype with filters
    try {
      debugPrint('getMyOrders fallback: fetching from ServePOS Waiter Order doctype');
      final list = await getList(
        'ServePOS Waiter Order',
        fields: ['name', 'waiter', 'waiter_name', 'table', 'room', 'order_type',
                 'guests', 'status', 'notes', 'edit_log', 'creation'],
        filters: [['waiter_name', '=', waiterName]],
        orderBy: 'creation desc',
      );
      if (list.isEmpty) {
        // Try filtering by waiter field instead
        final list2 = await getList(
          'ServePOS Waiter Order',
          fields: ['name', 'waiter', 'waiter_name', 'table', 'room', 'order_type',
                   'guests', 'status', 'notes', 'edit_log', 'creation'],
          filters: [['waiter', 'like', '%$waiterName%']],
          orderBy: 'creation desc',
        );
        if (list2.isNotEmpty) {
          return await _fetchOrdersWithItems(list2);
        }
      }
      return await _fetchOrdersWithItems(list);
    } catch (e) {
      debugPrint('getMyOrders fallback error: $e');
    }
    return [];
  }

  Future<List<WaiterOrder>> _fetchOrdersWithItems(List<dynamic> orderList) async {
    final orders = <WaiterOrder>[];
    for (final o in orderList) {
      try {
        final doc = await getDoc('ServePOS Waiter Order', o['name']);
        orders.add(WaiterOrder.fromJson(doc));
      } catch (e) {
        // If can't fetch full doc, create order without items
        orders.add(WaiterOrder.fromJson(o as Map<String, dynamic>));
      }
    }
    return orders;
  }

  Future<void> updateOrderStatus(String orderName, String status) async {
    await callMethod('servepos.api.waiter.update_order_status', args: {
      'order_name': orderName,
      'status': status,
    });
  }
}
