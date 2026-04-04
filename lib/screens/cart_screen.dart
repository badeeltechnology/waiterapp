import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/orders_provider.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Summary'),
        actions: [
          if (cart.items.isNotEmpty)
            TextButton(
              onPressed: () => cart.clearCart(),
              child: const Text('Clear', style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
      body: cart.items.isEmpty
        ? const Center(child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text('Cart is empty', style: TextStyle(color: Colors.grey, fontSize: 16)),
              SizedBox(height: 8),
              Text('Add items from the menu', style: TextStyle(color: Colors.grey)),
            ],
          ))
        : Column(
            children: [
              // Order type & table info
              Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withAlpha(50),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.primary.withAlpha(30)),
                ),
                child: Column(
                  children: [
                    // Order type
                    Row(children: [
                      const Text('Order Type:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const Spacer(),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'Dine In', label: Text('Dine In', style: TextStyle(fontSize: 11))),
                          ButtonSegment(value: 'Takeaway', label: Text('Takeaway', style: TextStyle(fontSize: 11))),
                          ButtonSegment(value: 'Delivery', label: Text('Delivery', style: TextStyle(fontSize: 11))),
                        ],
                        selected: {cart.orderType},
                        onSelectionChanged: (v) => cart.setOrderType(v.first),
                        style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
                      ),
                    ]),
                    if (cart.tableName != null) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        const Icon(Icons.table_restaurant, size: 16, color: Colors.grey),
                        const SizedBox(width: 6),
                        Text('Table: ${cart.tableName}', style: const TextStyle(fontWeight: FontWeight.w500)),
                        if (cart.room != null) Text('  (${cart.room})', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                      ]),
                    ],
                    const SizedBox(height: 8),
                    Row(children: [
                      const Text('Guests:', style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                        onPressed: cart.guests > 1 ? () => cart.setGuests(cart.guests - 1) : null,
                        visualDensity: VisualDensity.compact,
                      ),
                      Text('${cart.guests}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, size: 20),
                        onPressed: () => cart.setGuests(cart.guests + 1),
                        visualDensity: VisualDensity.compact,
                      ),
                    ]),
                  ],
                ),
              ),

              // Items list
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: cart.items.length,
                  itemBuilder: (_, i) {
                    final item = cart.items[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.itemName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  if (item.itemNameAr != null)
                                    Text(item.itemNameAr!, style: TextStyle(fontSize: 12, color: Colors.grey[600]), textDirection: TextDirection.rtl),
                                  Text('${item.rate.toStringAsFixed(2)} each', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                                ],
                              )),
                              // Qty controls
                              Row(children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, size: 22),
                                  onPressed: () => cart.updateQty(i, item.qty - 1),
                                  visualDensity: VisualDensity.compact,
                                ),
                                Text('${item.qty}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline, size: 22),
                                  onPressed: () => cart.updateQty(i, item.qty + 1),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ]),
                              SizedBox(
                                width: 70,
                                child: Text(item.amount.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.right),
                              ),
                            ]),
                            // Modifiers
                            if (item.modifiers.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Wrap(
                                  spacing: 6,
                                  children: item.modifiers.map((m) => Chip(
                                    label: Text(m.price > 0 ? '${m.name} +${m.price.toStringAsFixed(2)}' : m.name, style: const TextStyle(fontSize: 10)),
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  )).toList(),
                                ),
                              ),
                            // Special instructions
                            if (item.specialInstructions != null && item.specialInstructions!.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('"${item.specialInstructions}"', style: TextStyle(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic)),
                              ),
                            // Add instructions button
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                icon: const Icon(Icons.edit_note, size: 16),
                                label: const Text('Notes', style: TextStyle(fontSize: 11)),
                                onPressed: () async {
                                  final controller = TextEditingController(text: item.specialInstructions);
                                  final result = await showDialog<String>(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                      title: const Text('Special Instructions'),
                                      content: TextField(controller: controller, maxLines: 3, decoration: const InputDecoration(hintText: 'e.g., No onion, extra spicy...')),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                                        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
                                      ],
                                    ),
                                  );
                                  if (result != null) cart.updateSpecialInstructions(i, result.isEmpty ? null : result);
                                },
                                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Notes
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  onChanged: (v) => cart.setNotes(v.isEmpty ? null : v),
                  decoration: InputDecoration(
                    hintText: 'Order notes...',
                    prefixIcon: const Icon(Icons.note_alt_outlined, size: 18),
                    filled: true,
                    fillColor: Colors.grey[50],
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),

              // Total & Submit
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black.withAlpha(15), blurRadius: 10, offset: const Offset(0, -2))],
                ),
                child: SafeArea(
                  child: Column(children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('${cart.total.toStringAsFixed(2)} QAR', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (cart.error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(cart.error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                      ),
                    FilledButton.icon(
                      onPressed: cart.isSubmitting ? null : () async {
                        if (cart.orderType == 'Dine In' && cart.tableName == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please select a table for Dine In orders')),
                          );
                          return;
                        }
                        final waiterName = context.read<AuthProvider>().waiterName;
                        final order = await cart.submitOrder(waiterName);
                        if (order != null && context.mounted) {
                          await context.read<OrdersProvider>().loadOrders();
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Order ${order['name'] ?? ''} sent to kitchen!'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      },
                      icon: cart.isSubmitting
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send),
                      label: Text(cart.isSubmitting ? 'Sending...' : 'Send Order to Kitchen'),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              ),
            ],
          ),
    );
  }
}
