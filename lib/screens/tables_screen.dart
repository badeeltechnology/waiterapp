import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/table_provider.dart';
import '../providers/cart_provider.dart';
import '../models/models.dart';

class TablesScreen extends StatelessWidget {
  const TablesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<TableProvider>();
    final cart = context.watch<CartProvider>();
    final theme = Theme.of(context);

    return Column(
      children: [
        // Room tabs
        if (tp.rooms.isNotEmpty)
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('All Rooms'),
                    selected: tp.selectedRoom == null,
                    onSelected: (_) => tp.selectRoom(null),
                  ),
                ),
                ...tp.rooms.map((r) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _legendDot(Colors.green, 'Available'),
              const SizedBox(width: 16),
              _legendDot(Colors.red, 'Occupied'),
              const SizedBox(width: 16),
              _legendDot(Colors.orange, 'Reserved'),
              const SizedBox(width: 16),
              _legendDot(Colors.grey, 'Blocked'),
            ],
          ),
        ),

        // Tables grid
        Expanded(
          child: tp.isLoading
            ? const Center(child: CircularProgressIndicator())
            : tp.tables.isEmpty
              ? Center(child: Text('No tables found', style: TextStyle(color: Colors.grey[500])))
              : RefreshIndicator(
                  onRefresh: () => tp.loadTables(),
                  child: GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 1.0,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: tp.tables.length,
                    itemBuilder: (_, i) {
                      final t = tp.tables[i];
                      final isSelected = cart.tableName == t.name;
                      final isAvailable = t.status == 'Available' || isSelected;

                      return Card(
                        elevation: isSelected ? 4 : 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: isSelected
                            ? BorderSide(color: theme.colorScheme.primary, width: 2)
                            : BorderSide.none,
                        ),
                        color: isSelected ? theme.colorScheme.primaryContainer : null,
                        child: InkWell(
                          onTap: isAvailable ? () {
                            if (isSelected) {
                              cart.setTable(null, null);
                            } else {
                              cart.setTable(t.name, t.room);
                              cart.setOrderType('Dine In');
                            }
                          } : null,
                          borderRadius: BorderRadius.circular(12),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.table_restaurant,
                                size: 28,
                                color: _statusColor(t.status),
                              ),
                              const SizedBox(height: 6),
                              Text(t.tableName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), textAlign: TextAlign.center),
                              Text('${t.capacity} seats', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _statusColor(t.status).withAlpha(25),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(t.status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _statusColor(t.status))),
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
    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontSize: 11)),
  ]);
}
