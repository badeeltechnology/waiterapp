import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:badges/badges.dart' as badges;
import 'package:firebase_messaging/firebase_messaging.dart';
import '../providers/auth_provider.dart';
import '../providers/menu_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/orders_provider.dart';
import '../providers/table_provider.dart';
import '../providers/calls_provider.dart';
import '../api/erpnext_client.dart';
import '../models/models.dart';
import 'tables_screen.dart';
import 'orders_screen.dart';
import 'calls_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final auth = context.read<AuthProvider>();
    final menu = context.read<MenuProvider>();
    final orders = context.read<OrdersProvider>();
    final tables = context.read<TableProvider>();
    final calls = context.read<CallsProvider>();

    orders.setWaiterName(auth.waiterName);
    calls.setWaiterName(auth.waiterName);

    await Future.wait([
      menu.loadMenu(),
      orders.loadOrders(),
      tables.loadTables(),
      calls.loadCalls(),
    ]);

    orders.startPolling();
    calls.startPolling();

    // Setup FCM
    _setupFCM(auth.waiterName);
  }

  Future<void> _setupFCM(String waiterName) async {
    try {
      final messaging = FirebaseMessaging.instance;

      // Request permission
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Get and register FCM token
      final token = await messaging.getToken();
      if (token != null && waiterName.isNotEmpty) {
        try {
          await ERPNextClient().registerFcmToken(waiterName, token);
          debugPrint('FCM token registered');
        } catch (e) {
          debugPrint('FCM token registration failed: $e');
        }
      }

      // Listen for token refresh
      messaging.onTokenRefresh.listen((newToken) async {
        try {
          await ERPNextClient().registerFcmToken(waiterName, newToken);
        } catch (_) {}
      });

      // Foreground messages
      FirebaseMessaging.onMessage.listen((message) {
        final data = message.data;
        final calls = context.read<CallsProvider>();

        if (data['type'] == 'waiter_call') {
          final call = WaiterCall.fromFcmData(data);
          calls.onNewCall(call);
        } else if (data['type'] == 'waiter_call_accepted') {
          calls.onCallAccepted(data['call_name'] ?? '', data['accepted_by'] ?? '');
        }
      });

      // When user taps notification from background
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        final data = message.data;
        if (data['type'] == 'waiter_call') {
          setState(() => _currentIndex = 1); // Switch to Calls tab
          final calls = context.read<CallsProvider>();
          calls.onNewCall(WaiterCall.fromFcmData(data));
        }
      });
    } catch (e) {
      debugPrint('FCM setup skipped: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final cart = context.watch<CartProvider>();
    final orders = context.watch<OrdersProvider>();
    final calls = context.watch<CallsProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.restaurant, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ServePOS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                Text(auth.waiterName, style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ),
        actions: [
          // Online/offline indicator
          if (!cart.isOnline)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.wifi_off, size: 14, color: Colors.red.shade700),
                const SizedBox(width: 4),
                Text('Offline', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
              ]),
            ),

          // Queued orders count
          if (cart.queuedCount > 0)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(12)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.cloud_upload_outlined, size: 14, color: Colors.orange.shade700),
                const SizedBox(width: 4),
                Text('${cart.queuedCount} queued', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange.shade700)),
              ]),
            ),

          // Refresh
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Refresh',
          ),

          // Profile menu
          PopupMenuButton<String>(
            icon: CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                auth.waiterName.isNotEmpty ? auth.waiterName[0].toUpperCase() : '?',
                style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            onSelected: (value) {
              if (value == 'logout') {
                orders.stopPolling();
                auth.logout();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(auth.waiterName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text('Waiter', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                ]),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'logout', child: Row(children: [Icon(Icons.logout, size: 18, color: Colors.red), SizedBox(width: 10), Text('Logout', style: TextStyle(color: Colors.red))])),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          // Main content
          [const TablesScreen(), const CallsScreen(), const OrdersScreen()][_currentIndex],

          // Incoming call alert overlay
          if (calls.hasIncoming)
            IncomingCallAlert(
              call: calls.incomingCall!,
              onAccept: () async {
                final success = await calls.acceptCall(calls.incomingCall!.name);
                if (success) {
                  setState(() => _currentIndex = 1); // Switch to Calls tab
                }
              },
              onDismiss: () => calls.dismissIncoming(),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 65,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.table_restaurant_outlined),
            selectedIcon: Icon(Icons.table_restaurant),
            label: 'Tables',
          ),
          NavigationDestination(
            icon: badges.Badge(
              showBadge: calls.pendingCount > 0 || calls.activeCount > 0,
              badgeContent: Text('${calls.pendingCount + calls.activeCount}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
              badgeStyle: badges.BadgeStyle(badgeColor: calls.pendingCount > 0 ? Colors.orange : Colors.blue),
              child: Icon(calls.pendingCount > 0 ? Icons.notifications_active : Icons.call_outlined,
                color: calls.pendingCount > 0 ? Colors.orange : null),
            ),
            selectedIcon: const Icon(Icons.call),
            label: calls.pendingCount > 0 ? 'NEW CALL!' : 'Calls',
          ),
          NavigationDestination(
            icon: badges.Badge(
              showBadge: orders.activeOrders.isNotEmpty,
              badgeContent: Text('${orders.activeOrders.length}', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
              badgeStyle: badges.BadgeStyle(badgeColor: orders.hasReadyAlert ? Colors.red : theme.colorScheme.primary),
              child: Icon(orders.hasReadyAlert ? Icons.notifications_active : Icons.receipt_long_outlined,
                color: orders.hasReadyAlert ? Colors.red : null),
            ),
            selectedIcon: const Icon(Icons.receipt_long),
            label: orders.hasReadyAlert ? 'READY!' : 'My Orders',
          ),
        ],
      ),
    );
  }
}
