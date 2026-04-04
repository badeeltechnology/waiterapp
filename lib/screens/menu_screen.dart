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
  bool _gridView = true;

  @override
  void dispose() {
    _searchController.dispose();
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${item.itemName} added'), duration: const Duration(milliseconds: 800), backgroundColor: Colors.green),
          );
        }
      }
    } else {
      cart.addItem(CartItem(itemCode: item.itemCode, itemName: item.itemName, itemNameAr: item.itemNameAr, rate: item.rate));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${item.itemName} added'), duration: const Duration(milliseconds: 800), backgroundColor: Colors.green),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final menu = context.watch<MenuProvider>();
    final theme = Theme.of(context);

    final displayItems = _searchQuery.isNotEmpty
      ? menu.search(_searchQuery)
      : menu.filteredItems;

    return Column(
      children: [
        // Search bar with view toggle
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: 'Search items...',
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
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
                child: IconButton(
                  icon: Icon(_gridView ? Icons.view_list : Icons.grid_view, size: 20),
                  onPressed: () => setState(() => _gridView = !_gridView),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),

        // Category chips
        if (_searchQuery.isEmpty)
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text('All (${menu.allItems.length})', style: const TextStyle(fontSize: 12)),
                    selected: menu.selectedGroup == null,
                    onSelected: (_) => menu.selectGroup(null),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                ...menu.groups.map((g) {
                  final count = menu.allItems.where((i) => i.itemGroup == g.name).length;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text('${g.name} ($count)', style: const TextStyle(fontSize: 12)),
                      selected: menu.selectedGroup == g.name,
                      onSelected: (_) => menu.selectGroup(g.name == menu.selectedGroup ? null : g.name),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                }),
              ],
            ),
          ),

        const SizedBox(height: 4),

        // Items count
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text('${displayItems.length} items', style: TextStyle(fontSize: 12, color: Colors.grey[500], fontWeight: FontWeight.w500)),
            ],
          ),
        ),

        const SizedBox(height: 4),

        // Items
        Expanded(
          child: menu.isLoading
            ? const Center(child: CircularProgressIndicator())
            : displayItems.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.search_off, size: 48, color: Colors.grey[300]),
                  const SizedBox(height: 8),
                  Text('No items found', style: TextStyle(color: Colors.grey[500])),
                ]))
              : RefreshIndicator(
                  onRefresh: () => menu.loadMenu(),
                  child: _gridView
                    ? GridView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2, childAspectRatio: 0.78, crossAxisSpacing: 10, mainAxisSpacing: 10,
                        ),
                        itemCount: displayItems.length,
                        itemBuilder: (_, i) => _GridItemCard(item: displayItems[i], onTap: () => _addToCart(displayItems[i])),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                        itemCount: displayItems.length,
                        itemBuilder: (_, i) => _ListItemCard(item: displayItems[i], onTap: () => _addToCart(displayItems[i])),
                      ),
                ),
        ),
      ],
    );
  }
}

class _GridItemCard extends StatelessWidget {
  final MenuItem item;
  final VoidCallback onTap;
  const _GridItemCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                color: Colors.grey[50],
                child: item.image != null && item.image!.isNotEmpty
                  ? Image.network('${ERPNextClient().baseUrl}${item.image}', fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder())
                  : _placeholder(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.itemName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (item.itemNameAr != null)
                    Text(item.itemNameAr!, style: TextStyle(fontSize: 11, color: Colors.grey[500]), textDirection: TextDirection.rtl, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${item.rate.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary, fontSize: 15)),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
                        child: Icon(Icons.add, size: 16, color: theme.colorScheme.primary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Center(child: Icon(Icons.fastfood_outlined, size: 32, color: Colors.grey[300]));
}

class _ListItemCard extends StatelessWidget {
  final MenuItem item;
  final VoidCallback onTap;
  const _ListItemCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 48, height: 48,
          decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
          child: item.image != null && item.image!.isNotEmpty
            ? ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network('${ERPNextClient().baseUrl}${item.image}', fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder()))
            : _placeholder(),
        ),
        title: Text(item.itemName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: item.itemNameAr != null
          ? Text(item.itemNameAr!, style: TextStyle(fontSize: 12, color: Colors.grey[500]), textDirection: TextDirection.rtl)
          : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${item.rate.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary, fontSize: 15)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.add, size: 18, color: theme.colorScheme.primary),
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _placeholder() => Center(child: Icon(Icons.fastfood_outlined, size: 24, color: Colors.grey[300]));
}
