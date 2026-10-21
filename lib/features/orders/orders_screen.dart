import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/models/order.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../order/menu_repository.dart';
import '../order/outbox.dart';
import 'order_detail_screen.dart';
import 'orders_controller.dart';
import 'outbox_sheet.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<OrdersController>();
    final outbox = context.watch<Outbox>();
    final money = context.watch<MenuRepository>().money;
    final now = ServerClock.now();
    final present = <OrderStatus>{for (final o in c.orders) o.status}.toList()..sort((a, b) => a.index.compareTo(b.index));
    final list = c.visible;
    final readyList = c.orders.where((o) => c.readyUnseen.contains(o.name)).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(context.t('nav_orders')),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: SegmentedButton<bool>(
              style: SegmentedButton.styleFrom(
                backgroundColor: Nami.rail,
                foregroundColor: Nami.white,
                selectedBackgroundColor: Nami.amber,
                selectedForegroundColor: Nami.ink,
                side: const BorderSide(color: Nami.rail),
                minimumSize: const Size(48, 48),
                textStyle: const TextStyle(fontFamily: Nami.bodyFont, fontSize: 15, fontWeight: FontWeight.w600),
              ),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: false, label: Text(context.t('orders_mine'))),
                ButtonSegment(value: true, label: Text(context.t('orders_all'))),
              ],
              selected: {c.showAll},
              onSelectionChanged: (s) => c.setShowAll(s.first),
            ),
          ),
        ),
      ),
      body: Column(children: [
        if (present.length > 1)
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              children: [
                _FilterChip(label: context.t('floor_all'), selected: c.filter == null, onTap: () => c.setFilter(null)),
                for (final s in present)
                  _FilterChip(
                    label: '${context.t(s.labelKey)} ${c.orders.where((o) => o.status == s).length}',
                    selected: c.filter == s,
                    color: s.color,
                    onTap: () => c.setFilter(c.filter == s ? null : s),
                  ),
              ],
            ),
          ),
        if (c.error != null && c.orders.isNotEmpty)
          StatusStrip(text: context.t('orders_load_failed'), color: Nami.line, textColor: Nami.ink, icon: Icons.sync_problem),
        if (readyList.isNotEmpty)
          StatusStrip(
            text: context.t('orders_ready_banner', {'list': readyList.map((o) => o.table ?? o.name).join(', ')}),
            color: Nami.green,
            icon: Icons.room_service,
          ),
        Expanded(
          child: RefreshIndicator(
            color: Nami.teal,
            onRefresh: c.refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                // Unconfirmed orders first, clearly not "sent".
                for (final e in outbox.entries) OutboxCard(entry: e, money: money),
                if (list.isEmpty && outbox.entries.isEmpty)
                  SizedBox(
                    height: 300,
                    child: c.loading
                        ? const Center(child: CircularProgressIndicator())
                        : EmptyState(
                            icon: Icons.receipt_long_outlined,
                            text: c.error != null ? c.error!.message : context.t('orders_empty'),
                            action: c.error != null ? OutlinedButton(onPressed: c.refresh, child: Text(context.t('retry'))) : null,
                          ),
                  ),
                for (final o in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: OrderCard(
                      order: o,
                      money: money,
                      now: now,
                      highlight: c.readyUnseen.contains(o.name),
                      onTap: () {
                        c.markReadySeen(o.name);
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => OrderDetailScreen(name: o.name, initial: o)));
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap, this.color});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: Material(
          color: selected ? Nami.deep : Nami.white,
          borderRadius: BorderRadius.circular(Nami.radius),
          child: InkWell(
            borderRadius: BorderRadius.circular(Nami.radius),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              constraints: const BoxConstraints(minHeight: 44),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(Nami.radius), border: Border.all(color: selected ? Nami.deep : Nami.line)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (color != null) ...[
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                ],
                Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: selected ? Nami.white : Nami.ink)),
              ]),
            ),
          ),
        ),
      );
}

class OrderCard extends StatelessWidget {
  const OrderCard({super.key, required this.order, required this.money, required this.now, required this.onTap, this.highlight = false});
  final Order order;
  final Money money;
  final DateTime now;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final where = o.isTakeaway ? context.t('takeaway') : [o.table, o.room].whereType<String>().join(' · ');
    return NamiCard(
      onTap: onTap,
      border: highlight ? Border.all(color: Nami.green, width: 3) : BorderDirectional(start: BorderSide(color: o.status.color, width: 5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Text(where, style: Nami.num(26)),
                const SizedBox(width: 8),
                Flexible(child: Text(o.name, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Nami.muted, fontSize: 13))),
              ]),
              const SizedBox(height: 2),
              Text(
                [
                  if (o.waiter != null) o.waiter!,
                  if (o.guests > 0) context.t('order_guests_n', {'n': o.guests}),
                  context.t('order_items', {'n': CartQty.fmt(o.itemCount)}),
                ].join(' · '),
                style: const TextStyle(color: Nami.muted, fontSize: 14),
              ),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            StatusChip(o.status),
            const SizedBox(height: 6),
            Text(context.t('min', {'n': minutesSince(o.created, now)}), style: Nami.num(18, weight: FontWeight.w600, color: Nami.muted)),
          ]),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: Text(
              o.items.take(3).map((l) => '${CartQty.fmt(l.qty)}× ${l.itemName}').join(', ') + (o.items.length > 3 ? ' …' : ''),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          const SizedBox(width: 8),
          Text(money.amount(o.total), style: Nami.num(22)),
        ]),
      ]),
    );
  }
}

class CartQty {
  static String fmt(double q) => q == q.roundToDouble() ? '${q.toInt()}' : q.toStringAsFixed(1);
}
