import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:badges/badges.dart' as badges;
import '../providers/auth_provider.dart';
import '../providers/menu_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/orders_provider.dart';
import '../providers/table_provider.dart';
import 'tables_screen.dart';
import 'orders_screen.dart';

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

    orders.setWaiterName(auth.waiterName);

    await Future.wait([
      menu.loadMenu(),
      orders.loadOrders(),
      tables.loadTables(),
    ]);

    orders.startPolling();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final cart = context.watch<CartProvider>();
    final orders = context.watch<OrdersProvider>();
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
      body: _currentIndex == 0 ? const TablesScreen() : const OrdersScreen(),
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
