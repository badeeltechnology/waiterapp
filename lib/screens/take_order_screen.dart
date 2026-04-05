import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/erpnext_client.dart';
import '../providers/auth_provider.dart';
import '../providers/menu_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/orders_provider.dart';
import '../providers/table_provider.dart';
import '../models/models.dart';
import '../widgets/modifier_sheet.dart';

class TakeOrderScreen extends StatefulWidget {
  final TableInfo table;
  const TakeOrderScreen({super.key, required this.table});

  @override
  State<TakeOrderScreen> createState() => _TakeOrderScreenState();
}

class _TakeOrderScreenState extends State<TakeOrderScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showCart = false;
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final cart = context.read<CartProvider>();
    cart.setTable(widget.table.name, widget.table.room);
    cart.setOrderType('Dine In');
  }

  @override
  void dispose() {
    _searchController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _addToCart(MenuItem item) async {
    final menu = context.read<MenuProvider>();
    final cart = context.read<CartProvider>();

    final modGroups = await menu.getItemModifiers(item.itemCode);

    if (modGroups.isNotEmpty && mounted) {
      final result = await showModalBottomSheet<CartItem>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ModifierSheet(item: item, modifierGroups: modGroups),
      );
      if (result != null) {
        cart.addItem(result);
        if (mounted) _showAddedFeedback(item.itemName);
      }
    } else {
      cart.addItem(CartItem(
        itemCode: item.itemCode,
        itemName: item.itemName,
        itemNameAr: item.itemNameAr,
        rate: item.rate,
      ));
      if (mounted) _showAddedFeedback(item.itemName);
    }
  }

  void _showAddedFeedback(String name) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$name added'),
        duration: const Duration(milliseconds: 600),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 70),
      ),
    );
  }

  Future<void> _submitOrder() async {
    final cart = context.read<CartProvider>();
    if (cart.items.isEmpty) return;

    final notes = _notesController.text.trim();
    if (notes.isNotEmpty) cart.setNotes(notes);

    final waiterName = context.read<AuthProvider>().waiterName;
    final order = await cart.submitOrder(waiterName);

    if (order != null && mounted) {
      await context.read<OrdersProvider>().loadOrders();
      await context.read<TableProvider>().loadTables();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order ${order['name'] ?? 'queued'} sent to kitchen!'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final menu = context.watch<MenuProvider>();
    final cart = context.watch<CartProvider>();
    final theme = Theme.of(context);

    final displayItems = _searchQuery.isNotEmpty
      ? menu.search(_searchQuery)
      : menu.filteredItems;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                widget.table.tableName,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('New Order', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                if (widget.table.room != null)
                  Text(widget.table.room!, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
              ],
            ),
          ],
        ),
        actions: [
          // Guest count
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.people_outline, size: 16),
                IconButton(
                  icon: const Icon(Icons.remove, size: 16),
                  onPressed: cart.guests > 1 ? () => cart.setGuests(cart.guests - 1) : null,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
                Text('${cart.guests}', style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.add, size: 16),
                  onPressed: () => cart.setGuests(cart.guests + 1),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: InputDecoration(
                hintText: 'Search menu...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); })
                  : null,
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                isDense: true,
              ),
            ),
          ),

          // Category chips
          if (_searchQuery.isEmpty)
            Container(
              color: Colors.white,
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text('All (${menu.allItems.length})', style: const TextStyle(fontSize: 12)),
                      selected: menu.selectedGroup == null,
                      onSelected: (_) => menu.selectGroup(null),
                      showCheckmark: false,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  ...menu.groups.map((g) {
                    final count = menu.allItems.where((i) => i.itemGroup == g.name).length;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text('${g.name} ($count)', style: const TextStyle(fontSize: 12)),
                        selected: menu.selectedGroup == g.name,
                        onSelected: (_) => menu.selectGroup(g.name == menu.selectedGroup ? null : g.name),
                        showCheckmark: false,
                        visualDensity: VisualDensity.compact,
                      ),
                    );
                  }),
                ],
              ),
            ),

          const SizedBox(height: 4),

          // Menu items
          Expanded(
            child: menu.isLoading
              ? const Center(child: CircularProgressIndicator())
              : displayItems.isEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.search_off, size: 48, color: Colors.grey[300]),
                    const SizedBox(height: 8),
                    Text('No items found', style: TextStyle(color: Colors.grey[500])),
                  ]))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 100),
                    itemCount: displayItems.length,
                    itemBuilder: (_, i) => _MenuItemTile(
                      item: displayItems[i],
                      onAdd: () => _addToCart(displayItems[i]),
                    ),
                  ),
          ),
        ],
      ),

      // Bottom cart bar
      bottomNavigationBar: cart.items.isEmpty
        ? null
        : _CartBottomBar(
            cart: cart,
            showCart: _showCart,
            notesController: _notesController,
            onToggle: () => setState(() => _showCart = !_showCart),
            onSubmit: cart.isSubmitting ? null : _submitOrder,
          ),
    );
  }
}

// --- Menu item tile ---
class _MenuItemTile extends StatelessWidget {
  final MenuItem item;
  final VoidCallback onAdd;

  const _MenuItemTile({required this.item, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        onTap: onAdd,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // Item image
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: item.image != null && item.image!.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        '${ERPNextClient().baseUrl}${item.image}',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholder(),
                      ),
                    )
                  : _placeholder(),
              ),
              const SizedBox(width: 12),

              // Item details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.itemName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    if (item.itemNameAr != null)
                      Text(item.itemNameAr!, style: TextStyle(fontSize: 12, color: Colors.grey[500]), textDirection: TextDirection.rtl),
                  ],
                ),
              ),

              // Price
              Text(
                '${item.rate.toStringAsFixed(item.rate == item.rate.roundToDouble() ? 0 : 2)}',
                style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary, fontSize: 15),
              ),
              const SizedBox(width: 8),

              // Add button
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add, size: 20, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() => Center(child: Icon(Icons.fastfood_outlined, size: 24, color: Colors.grey[300]));
}

// --- Bottom cart bar ---
class _CartBottomBar extends StatelessWidget {
  final CartProvider cart;
  final bool showCart;
  final TextEditingController notesController;
  final VoidCallback onToggle;
  final VoidCallback? onSubmit;

  const _CartBottomBar({
    required this.cart,
    required this.showCart,
    required this.notesController,
    required this.onToggle,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 10, offset: const Offset(0, -2))],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cart header (always visible)
            GestureDetector(
              onTap: onToggle,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${cart.itemCount}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${cart.itemCount} item${cart.itemCount > 1 ? 's' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const Spacer(),
                    Text(
                      '${cart.total.toStringAsFixed(2)} QAR',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 8),
                    Icon(showCart ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up, color: Colors.grey),
                  ],
                ),
              ),
            ),

            // Expanded cart items (when showCart is true)
            if (showCart) ...[
              const Divider(height: 1),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.35),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  itemCount: cart.items.length,
                  itemBuilder: (_, i) => _CartItemRow(
                    item: cart.items[i],
                    index: i,
                    cart: cart,
                  ),
                ),
              ),
              // Order notes
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: TextField(
                  controller: notesController,
                  decoration: InputDecoration(
                    hintText: 'Order notes...',
                    prefixIcon: const Icon(Icons.note_alt_outlined, size: 16),
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],

            // Submit button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: FilledButton.icon(
                onPressed: onSubmit,
                icon: cart.isSubmitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded),
                label: Text(
                  cart.isSubmitting ? 'Sending...' : 'Send to Kitchen',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartItemRow extends StatelessWidget {
  final CartItem item;
  final int index;
  final CartProvider cart;

  const _CartItemRow({required this.item, required this.index, required this.cart});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Item info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.itemName, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (item.modifiers.isNotEmpty)
                  Text(
                    item.modifiers.map((m) => m.name).join(', '),
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                if (item.specialInstructions != null && item.specialInstructions!.isNotEmpty)
                  Text(
                    '"${item.specialInstructions}"',
                    style: TextStyle(fontSize: 10, color: Colors.grey[500], fontStyle: FontStyle.italic),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),

          // Qty controls
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _qtyButton(Icons.remove, () => cart.updateQty(index, item.qty - 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('${item.qty}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
              _qtyButton(Icons.add, () => cart.updateQty(index, item.qty + 1)),
            ],
          ),

          // Amount
          SizedBox(
            width: 60,
            child: Text(
              item.amount.toStringAsFixed(2),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _qtyButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 14),
      ),
    );
  }
}
