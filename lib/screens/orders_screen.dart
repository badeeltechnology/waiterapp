import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/orders_provider.dart';
import '../models/models.dart';
import 'package:intl/intl.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final op = context.watch<OrdersProvider>();

    return RefreshIndicator(
      onRefresh: () => op.loadOrders(),
      child: op.isLoading && op.orders.isEmpty
        ? const Center(child: CircularProgressIndicator())
        : op.orders.isEmpty
          ? const Center(child: Text('No orders yet', style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: op.orders.length,
              itemBuilder: (_, i) => _OrderCard(order: op.orders[i]),
            ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final WaiterOrder order;
  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _showOrderDetail(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(order.name, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace', fontSize: 14)),
                  _StatusBadge(status: order.status),
                ],
              ),
              const SizedBox(height: 8),

              // Info row
              Row(children: [
                Icon(Icons.restaurant, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(order.orderType, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                if (order.table != null) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.table_restaurant, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(order.table!, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
                if (order.creation != null) ...[
                  const Spacer(),
                  Text(
                    _formatTime(order.creation!),
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ]),

              const Divider(height: 16),

              // Items summary
              ...order.items.take(3).map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text('${item.qty.toInt()}x  ${item.itemName}', style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                    Text(item.amount.toStringAsFixed(2), style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                  ],
                ),
              )),
              if (order.items.length > 3)
                Text('+${order.items.length - 3} more items', style: TextStyle(fontSize: 11, color: Colors.grey[500])),

              const Divider(height: 16),

              // Total
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('${order.total.toStringAsFixed(2)} QAR', style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary, fontSize: 15)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(String creation) {
    try {
      final dt = DateTime.parse(creation);
      return DateFormat('hh:mm a').format(dt);
    } catch (_) {
      return creation;
    }
  }

  void _showOrderDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(order.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, fontFamily: 'monospace')),
                _StatusBadge(status: order.status),
              ],
            ),
            const SizedBox(height: 8),
            Text('${order.orderType}${order.table != null ? '  •  Table: ${order.table}' : ''}  •  Guests: ${order.guests}'),
            if (order.waiterName != null) Text('Waiter: ${order.waiterName}', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
            const Divider(height: 24),
            const Text('Items', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            ...order.items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 30, child: Text('${item.qty.toInt()}x', style: const TextStyle(fontWeight: FontWeight.w600))),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.itemName, style: const TextStyle(fontWeight: FontWeight.w500)),
                      if (item.specialInstructions != null)
                        Text('"${item.specialInstructions}"', style: TextStyle(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic)),
                    ],
                  )),
                  Text(item.amount.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w500)),
                ],
              ),
            )),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                Text('${order.total.toStringAsFixed(2)} QAR', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Theme.of(context).colorScheme.primary)),
              ],
            ),
            if (order.notes != null && order.notes!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Notes: ${order.notes}', style: TextStyle(color: Colors.grey[600])),
            ],
            if (order.status == 'Pending') ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () {
                  context.read<OrdersProvider>().cancelOrder(order.name);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                label: const Text('Cancel Order', style: TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  minimumSize: const Size.fromHeight(44),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withAlpha(25), borderRadius: BorderRadius.circular(12)),
      child: Text(status, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Color _getColor() {
    switch (status) {
      case 'Pending': return Colors.orange;
      case 'Accepted': return Colors.blue;
      case 'In Kitchen': return Colors.purple;
      case 'Ready': return Colors.green;
      case 'Served': return Colors.teal;
      case 'Paid': return Colors.grey;
      case 'Cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }
}
