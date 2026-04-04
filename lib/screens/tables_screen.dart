import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/table_provider.dart';
import '../providers/cart_provider.dart';

class TablesScreen extends StatelessWidget {
  const TablesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<TableProvider>();
    final cart = context.watch<CartProvider>();
    final theme = Theme.of(context);

    return Column(
      children: [
        // Selected table banner
        if (cart.tableName != null)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Table Selected: ${cart.tableName}', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                    if (cart.room != null) Text(cart.room!, style: TextStyle(fontSize: 12, color: theme.colorScheme.primary.withAlpha(180))),
                  ],
                )),
                TextButton(
                  onPressed: () => cart.setTable(null, null),
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),

        // Room tabs
        if (tp.rooms.isNotEmpty)
          Container(
            height: 52,
            margin: const EdgeInsets.only(top: 8),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('All Rooms'),
                    selected: tp.selectedRoom == null,
                    onSelected: (_) => tp.selectRoom(null),
                  ),
                ),
                ...tp.rooms.map((r) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(r.roomName),
                    selected: tp.selectedRoom == r.name,
                    onSelected: (_) => tp.selectRoom(r.name == tp.selectedRoom ? null : r.name),
                  ),
                )),
              ],
            ),
          ),

        // Legend
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              _legendDot(Colors.green, 'Available'),
              const SizedBox(width: 16),
              _legendDot(Colors.red, 'Occupied'),
              const SizedBox(width: 16),
              _legendDot(Colors.orange, 'Reserved'),
              const Spacer(),
              Text('${tp.tables.length} tables', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ],
          ),
        ),

        // Tables grid
        Expanded(
          child: tp.isLoading
            ? const Center(child: CircularProgressIndicator())
            : tp.tables.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.table_restaurant, size: 48, color: Colors.grey[300]),
                  const SizedBox(height: 8),
                  Text('No tables found', style: TextStyle(color: Colors.grey[500])),
                ]))
              : RefreshIndicator(
                  onRefresh: () => tp.loadTables(),
                  child: GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.9,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: tp.tables.length,
                    itemBuilder: (_, i) {
                      final t = tp.tables[i];
                      final isSelected = cart.tableName == t.name;
                      final isAvailable = t.status == 'Available' || isSelected;
                      final color = _statusColor(t.status);

                      return GestureDetector(
                        onTap: isAvailable ? () {
                          if (isSelected) {
                            cart.setTable(null, null);
                          } else {
                            cart.setTable(t.name, t.room);
                            cart.setOrderType('Dine In');
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Table ${t.tableName} selected'),
                                duration: const Duration(seconds: 1),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        } : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: isSelected ? theme.colorScheme.primaryContainer : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected ? theme.colorScheme.primary : color.withAlpha(80),
                              width: isSelected ? 3 : 1.5,
                            ),
                            boxShadow: isSelected ? [BoxShadow(color: theme.colorScheme.primary.withAlpha(40), blurRadius: 12, spreadRadius: 1)] : [BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 4)],
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Table icon
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isSelected ? theme.colorScheme.primary.withAlpha(30) : color.withAlpha(20),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  isSelected ? Icons.check_circle : Icons.table_restaurant,
                                  size: 28,
                                  color: isSelected ? theme.colorScheme.primary : color,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(t.tableName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isSelected ? theme.colorScheme.primary : null)),
                              const SizedBox(height: 2),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.person, size: 12, color: Colors.grey[500]),
                                  const SizedBox(width: 2),
                                  Text('${t.capacity}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isSelected ? theme.colorScheme.primary : color,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  isSelected ? 'Selected' : t.status,
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Available': return Colors.green;
      case 'Occupied': return Colors.red;
      case 'Reserved': return Colors.orange;
      case 'Blocked': return Colors.grey;
      default: return Colors.grey;
    }
  }

  Widget _legendDot(Color color, String label) => Row(children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontSize: 11)),
  ]);
}
