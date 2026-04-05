import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/table_provider.dart';
import '../models/models.dart';
import 'take_order_screen.dart';

class TablesScreen extends StatelessWidget {
  const TablesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<TableProvider>();

    return Column(
      children: [
        // Room/section tabs
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

        const SizedBox(height: 8),

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
                      childAspectRatio: 1.0,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: tp.tables.length,
                    itemBuilder: (_, i) => _TableCard(table: tp.tables[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _TableCard extends StatelessWidget {
  final TableInfo table;

  const _TableCard({required this.table});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TakeOrderScreen(table: table),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.primary.withAlpha(60), width: 1.5),
          boxShadow: [
            BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 4),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Table icon
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withAlpha(80),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.table_restaurant,
                size: 28,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),

            // Table name
            Text(
              table.tableName,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
