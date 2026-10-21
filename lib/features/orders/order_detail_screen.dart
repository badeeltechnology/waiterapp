import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/models/order.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../auth/session_controller.dart';
import '../order/cart.dart';
import '../order/menu_repository.dart';
import '../order/take_order_screen.dart';
import 'orders_controller.dart';
import 'orders_screen.dart' show CartQty;

class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({super.key, required this.name, this.initial});
  final String name;
  final Order? initial;
  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late Order? _order = widget.initial;
  ApiException? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final o = await context.read<OrdersController>().load(widget.name);
      if (mounted) setState(() => (_order = o, _error = null));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancel() async {
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(c.t('order_cancel')),
          content: TextField(
            controller: reason,
            autofocus: true,
            onChanged: (_) => set(() {}),
            decoration: InputDecoration(labelText: c.t('order_cancel_reason')),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(c.t('close'))),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Nami.red, foregroundColor: Nami.white, minimumSize: const Size(48, 48)),
              onPressed: reason.text.trim().isEmpty ? null : () => Navigator.pop(c, true),
              child: Text(c.t('order_cancel_confirm')),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<OrdersController>().cancel(widget.name, reason.text.trim());
      if (!mounted) return;
      showMessage(context, context.t('order_cancelled'));
      await _load();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    final money = context.watch<MenuRepository>().money;
    final session = context.watch<SessionController>();
    final allowCancel = context.watch<MenuRepository>().data?.settings.allowCancelPending ?? true;
    final mine = o?.waiter == null || o?.waiter == session.user?.waiter;
    final rounds = <int, List<OrderLine>>{};
    for (final l in o?.items ?? const <OrderLine>[]) {
      rounds.putIfAbsent(l.round, () => []).add(l);
    }
    final keys = rounds.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: Text(o == null ? widget.name : (o.isTakeaway ? context.t('takeaway') : (o.table ?? o.name))),
        actions: [IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh), tooltip: context.t('refresh'))],
      ),
      body: o == null
          ? (_loading ? const Center(child: CircularProgressIndicator()) : EmptyState(icon: Icons.error_outline, text: _error?.message ?? ''))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(12), children: [
                if (_error != null) StatusStrip(text: _error!.message, color: Nami.line, textColor: Nami.ink, icon: Icons.sync_problem),
                NamiCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(o.name, style: Nami.num(24))),
                      StatusChip(o.status, large: true),
                    ]),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (o.room != null) o.room!,
                        if (o.waiter != null) o.waiter!,
                        if (o.guests > 0) context.t('order_guests_n', {'n': o.guests}),
                        if (o.created != null) hhmm(o.created!),
                      ].join(' · '),
                      style: const TextStyle(color: Nami.muted, fontSize: 15),
                    ),
                    if (o.notes != null) ...[
                      const SizedBox(height: 8),
                      Text(o.notes!, style: const TextStyle(fontSize: 15, fontStyle: FontStyle.italic)),
                    ],
                  ]),
                ),
                for (final r in keys) ...[
                  SectionCap(
                    keys.length > 1 ? context.t('order_round', {'n': r}) : context.t('order_items', {'n': CartQty.fmt(o.itemCount)}),
                    trailing: rounds[r]!.first.addedBy == null
                        ? null
                        : Text(context.t('order_by', {'n': rounds[r]!.first.addedBy}), style: const TextStyle(color: Nami.muted, fontSize: 13)),
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
                  ),
                  NamiCard(
                    padding: EdgeInsets.zero,
                    child: Column(children: [
                      for (final l in rounds[r]!)
                        Container(
                          constraints: const BoxConstraints(minHeight: 52),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Nami.line))),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            SizedBox(width: 34, child: Text(CartQty.fmt(l.qty), style: Nami.num(22))),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(l.itemName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                                for (final m in l.modifiers)
                                  Text('+ ${m.name}${m.price == 0 ? '' : '  ${money.amount(m.price)}'}', style: const TextStyle(fontSize: 14, color: Nami.muted)),
                                if (l.specialInstructions != null)
                                  Text('“${l.specialInstructions}”', style: const TextStyle(fontSize: 14, color: Nami.teal, fontStyle: FontStyle.italic)),
                              ]),
                            ),
                            Text(money.amount(l.amount), style: Nami.num(20, weight: FontWeight.w600)),
                          ]),
                        ),
                    ]),
                  ),
                ],
                const SizedBox(height: 12),
                NamiCard(
                  child: Row(children: [
                    Expanded(child: Text(context.t('total'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
                    Text(money.withCode(o.total), style: Nami.num(28)),
                  ]),
                ),
                const SizedBox(height: 16),
                if (o.status.isOpen && !o.isTakeaway && o.table != null)
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(
                      builder: (_) => TakeOrderScreen(
                        target: CartTarget.table(table: o.table!, room: o.room, tableLabel: o.table),
                        openOrder: o.name,
                      ),
                    )),
                    icon: const Icon(Icons.add),
                    label: Text(context.t('order_add_more')),
                  ),
                if (o.status == OrderStatus.pending && allowCancel && mine) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    key: const Key('order_cancel'),
                    style: OutlinedButton.styleFrom(foregroundColor: Nami.red, side: const BorderSide(color: Nami.red, width: 1.5)),
                    onPressed: _cancel,
                    icon: const Icon(Icons.cancel_outlined),
                    label: Text(context.t('order_cancel')),
                  ),
                ],
              ]),
            ),
    );
  }
}
