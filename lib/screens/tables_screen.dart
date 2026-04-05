import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/table_provider.dart';
import '../providers/orders_provider.dart';
import '../models/models.dart';
import 'take_order_screen.dart';

class TablesScreen extends StatelessWidget {
  const TablesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<TableProvider>();
    final orders = context.watch<OrdersProvider>();
    final theme = Theme.of(context);

    return Column(
      children: [
        // Room tabs
        if (tp.rooms.isNotEmpty)
          Container(
            height: 56,
            padding: const EdgeInsets.only(top: 8),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text('All (${tp.allTables.length})'),
                    selected: tp.selectedRoom == null,
                    onSelected: (_) => tp.selectRoom(null),
                    showCheckmark: false,
                  ),
                ),
                ...tp.rooms.map((r) {
                  final count = tp.allTables.where((t) => t.room == r.name).length;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text('${r.roomName} ($count)'),
                      selected: tp.selectedRoom == r.name,
                      onSelected: (_) => tp.selectRoom(r.name == tp.selectedRoom ? null : r.name),
                      showCheckmark: false,
                    ),
                  );
                }),
              ],
            ),
          ),

        // Legend bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              _legendDot(Colors.green.shade600, 'Open'),
              const SizedBox(width: 14),
              _legendDot(Colors.red.shade400, 'Occupied'),
              const SizedBox(width: 14),
              _legendDot(Colors.orange.shade400, 'Reserved'),
              const Spacer(),
              Text('${tp.tables.length} tables', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            ],
          ),
        ),

        // Tables grid
        Expanded(
          child: tp.isLoading
            ? const Center(child: CircularProgressIndicator())
            : tp.tables.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.table_restaurant, size: 56, color: Colors.grey[300]),
                  const SizedBox(height: 12),
                  Text('No tables found', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
                ]))
              : RefreshIndicator(
                  onRefresh: () => tp.loadTables(),
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.85,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: tp.tables.length,
                    itemBuilder: (_, i) => _TableCard(
                      table: tp.tables[i],
                      activeOrder: _getActiveOrderForTable(orders, tp.tables[i].name),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  WaiterOrder? _getActiveOrderForTable(OrdersProvider orders, String tableName) {
    try {
      return orders.activeOrders.firstWhere((o) => o.table == tableName);
    } catch (_) {
      return null;
    }
  }

  Widget _legendDot(Color color, String label) => Row(children: [
    Container(
      width: 10, height: 10,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
    ),
    const SizedBox(width: 4),
    Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
  ]);
}

class _TableCard extends StatelessWidget {
  final TableInfo table;
  final WaiterOrder? activeOrder;

  const _TableCard({required this.table, this.activeOrder});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAvailable = table.status == 'Available';
    final isOccupied = table.status == 'Occupied';
    final isReady = activeOrder?.status == 'Ready';

    final Color cardColor;
    final Color borderColor;
    final Color iconColor;

    if (isReady) {
      cardColor = Colors.green.shade50;
      borderColor = Colors.green.shade400;
      iconColor = Colors.green.shade700;
    } else if (isAvailable) {
      cardColor = Colors.white;
      borderColor = Colors.green.shade200;
      iconColor = Colors.green.shade600;
    } else if (isOccupied) {
      cardColor = Colors.red.shade50;
      borderColor = Colors.red.shade200;
      iconColor = Colors.red.shade400;
    } else if (table.status == 'Reserved') {
      cardColor = Colors.orange.shade50;
      borderColor = Colors.orange.shade200;
      iconColor = Colors.orange.shade400;
    } else {
      cardColor = Colors.grey.shade100;
      borderColor = Colors.grey.shade300;
      iconColor = Colors.grey;
    }

    return GestureDetector(
      onTap: () {
        if (table.status == 'Blocked') return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TakeOrderScreen(table: table),
          ),
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: isReady ? 2.5 : 1.5),
          boxShadow: [
            BoxShadow(
              color: isReady ? Colors.green.withAlpha(30) : Colors.black.withAlpha(8),
              blurRadius: isReady ? 8 : 4,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Table icon with status
            Stack(
              alignment: Alignment.topRight,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: iconColor.withAlpha(20),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.table_restaurant,
                    size: 28,
                    color: iconColor,
                  ),
                ),
                if (isReady)
                  Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                    child: const Icon(Icons.notifications_active, size: 12, color: Colors.white),
                  ),
              ],
            ),
            const SizedBox(height: 6),

            // Table name
            Text(
              table.tableName,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isReady ? Colors.green.shade800 : null,
              ),
            ),

            // Capacity
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_outline, size: 12, color: Colors.grey[500]),
                const SizedBox(width: 2),
                Text('${table.capacity}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ),
            const SizedBox(height: 4),

            // Status badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: isReady ? Colors.green : iconColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                isReady ? 'Ready!' : isOccupied && activeOrder != null ? activeOrder!.status : table.status,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
