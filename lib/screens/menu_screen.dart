import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/erpnext_client.dart';
import '../providers/auth_provider.dart';
import '../providers/menu_provider.dart';
import '../providers/cart_provider.dart';
import '../models/models.dart';
import '../widgets/modifier_sheet.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _addToCart(MenuItem item) async {
    final menu = context.read<MenuProvider>();
    final cart = context.read<CartProvider>();

    // Check for modifiers
    final modGroups = await menu.getItemModifiers(item.itemCode);

    if (modGroups.isNotEmpty && mounted) {
      final result = await showModalBottomSheet<CartItem>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ModifierSheet(item: item, modifierGroups: modGroups),
      );
      if (result != null) cart.addItem(result);
    } else {
      cart.addItem(CartItem(
        itemCode: item.itemCode,
        itemName: item.itemName,
        itemNameAr: item.itemNameAr,
        rate: item.rate,
      ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${item.itemName} added'), duration: const Duration(seconds: 1)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final menu = context.watch<MenuProvider>();

    final displayItems = _searchQuery.isNotEmpty
      ? menu.search(_searchQuery)
      : menu.filteredItems;

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Search items...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); })
                : null,
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ),

        // Category chips
        if (_searchQuery.isEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('All'),
                    selected: menu.selectedGroup == null,
                    onSelected: (_) => menu.selectGroup(null),
                  ),
                ),
                ...menu.groups.map((g) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(g.name),
                    selected: menu.selectedGroup == g.name,
                    onSelected: (_) => menu.selectGroup(g.name == menu.selectedGroup ? null : g.name),
                  ),
                )),
              ],
            ),
          ),

        const SizedBox(height: 8),

        // Items grid
        Expanded(
          child: menu.isLoading
            ? const Center(child: CircularProgressIndicator())
            : displayItems.isEmpty
              ? Center(child: Text('No items found', style: TextStyle(color: Colors.grey[500])))
              : RefreshIndicator(
                  onRefresh: () => menu.loadMenu(),
                  child: GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.85,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: displayItems.length,
                    itemBuilder: (_, i) => _ItemCard(item: displayItems[i], onTap: () => _addToCart(displayItems[i])),
                  ),
                ),
        ),
      ],
    );
  }
}

class _ItemCard extends StatelessWidget {
  final MenuItem item;
  final VoidCallback onTap;

  const _ItemCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image or placeholder
            Expanded(
              child: Container(
                width: double.infinity,
                color: Colors.grey[100],
                child: item.image != null && item.image!.isNotEmpty
                  ? Image.network(
                      '${ERPNextClient().baseUrl}${item.image}',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(),
                    )
                  : _placeholder(),
              ),
            ),
            // Info
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.itemName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (item.itemNameAr != null)
                    Text(item.itemNameAr!, style: TextStyle(fontSize: 11, color: Colors.grey[600]), textDirection: TextDirection.rtl, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text('${item.rate.toStringAsFixed(2)} QAR', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary, fontSize: 14)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Center(child: Icon(Icons.fastfood_outlined, size: 36, color: Colors.grey[300]));
}
