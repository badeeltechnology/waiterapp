import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:badges/badges.dart' as badges;
import '../providers/auth_provider.dart';
import '../providers/menu_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/orders_provider.dart';
import '../providers/table_provider.dart';
import 'menu_screen.dart';
import 'orders_screen.dart';
import 'tables_screen.dart';
import 'cart_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final _screens = const [
    MenuScreen(),
    OrdersScreen(),
    TablesScreen(),
  ];

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('ServePOS', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          // Cart button
          if (cart.itemCount > 0)
            badges.Badge(
              position: badges.BadgePosition.topEnd(top: 0, end: 0),
              badgeContent: Text('${cart.itemCount}', style: const TextStyle(color: Colors.white, fontSize: 10)),
              child: IconButton(
                icon: const Icon(Icons.shopping_cart_outlined),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen())),
              ),
            ),
          if (cart.itemCount == 0)
            IconButton(
              icon: const Icon(Icons.shopping_cart_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen())),
            ),

          // Profile menu
          PopupMenuButton<String>(
            icon: CircleAvatar(
              radius: 16,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                auth.waiterName.isNotEmpty ? auth.waiterName[0].toUpperCase() : '?',
                style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
              ),
            ),
            onSelected: (value) {
              if (value == 'logout') {
                orders.stopPolling();
                auth.logout();
              } else if (value == 'refresh') {
                _loadData();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(auth.waiterName, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                  Text('Waiter', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ]),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'refresh', child: Row(children: [Icon(Icons.refresh, size: 18), SizedBox(width: 8), Text('Refresh Data')])),
              const PopupMenuItem(value: 'logout', child: Row(children: [Icon(Icons.logout, size: 18, color: Colors.red), SizedBox(width: 8), Text('Logout', style: TextStyle(color: Colors.red))])),
            ],
          ),
        ],
      ),
      body: _screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.restaurant_menu), label: 'Menu'),
          NavigationDestination(
            icon: badges.Badge(
              showBadge: orders.activeOrders.isNotEmpty,
              badgeContent: Text('${orders.activeOrders.length}', style: const TextStyle(color: Colors.white, fontSize: 10)),
              child: const Icon(Icons.receipt_long),
            ),
            label: 'Orders',
          ),
          const NavigationDestination(icon: Icon(Icons.table_restaurant), label: 'Tables'),
        ],
      ),
      // Floating cart button
      floatingActionButton: cart.itemCount > 0 ? FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen())),
        icon: const Icon(Icons.shopping_cart),
        label: Text('${cart.itemCount} items  -  ${cart.total.toStringAsFixed(2)}'),
      ) : null,
    );
  }
}
