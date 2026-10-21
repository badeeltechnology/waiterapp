import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/models/menu.dart';
import '../../core/models/order.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../auth/session_controller.dart';
import '../floor/floor_controller.dart';
import '../orders/orders_controller.dart';
import 'cart.dart';
import 'menu_repository.dart';
import 'modifier_sheet.dart';
import 'order_sender.dart';
import 'outbox.dart';

/// Take an order for one table (or takeaway). Each table keeps its own draft.
/// When the table already has an open order the new lines go out as a new
/// round (add_items) and the existing lines are shown as "Sent".
class TakeOrderScreen extends StatefulWidget {
  const TakeOrderScreen({super.key, required this.target, this.openOrder});
  final CartTarget target;
  final String? openOrder;

  @override
  State<TakeOrderScreen> createState() => _TakeOrderScreenState();
}

class _TakeOrderScreenState extends State<TakeOrderScreen> {
  String? _group; // null = all
  String _query = '';
  final _search = TextEditingController();
  Order? _existing;
  bool _loadingExisting = false;
  bool _sending = false;

  /// Live open order: the floor may have learned about it after we opened.
  String? get _openOrder {
    if (widget.target.takeaway) return null;
    final live = context.read<FloorController>().live(widget.target.table!);
    return live?.order?.order ?? widget.openOrder;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadExisting());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    final name = _openOrder;
    if (name == null || !mounted) return;
    setState(() => _loadingExisting = true);
    try {
      final o = await context.read<OrdersController>().load(name);
      if (mounted) setState(() => _existing = o);
    } on ApiException {
      // Offline: we still know the order name from the floor; lines unknown.
    } finally {
      if (mounted) setState(() => _loadingExisting = false);
    }
  }

  Future<void> _tapItem(MenuItem item, MenuData menu, Money money) async {
    if (!item.isAvailable) return;
    final carts = context.read<CartStore>();
    if (menu.hasMissingGroups(item)) {
      // Never add an item plain when its (maybe required) options are unknown.
      showMessage(context, context.t('order_mods_missing'), error: true);
      return;
    }
    final groups = menu.groupsFor(item);
    if (groups.isEmpty) {
      HapticFeedback.lightImpact();
      carts.add(widget.target.key, CartLine.fromItem(item));
      return;
    }
    final line = await showModifierSheet(context, item: item, groups: groups, money: money);
    if (line != null) carts.add(widget.target.key, line);
  }

  Future<void> _send() async {
    if (_sending) return;
    final session = context.read<SessionController>();
    final sender = context.read<OrderSender>();
    final floor = context.read<FloorController>();
    setState(() => _sending = true);
    try {
      final outcome = await sender.send(
        target: widget.target,
        posProfile: session.profile!.name,
        user: session.user!.user,
        existingOrder: _openOrder,
      );
      if (!mounted) return;
      switch (outcome) {
        case SentOutcome(:final order):
          HapticFeedback.mediumImpact();
          showMessage(context, context.t('order_sent_ok', {'name': order.name}));
          floor.refresh();
          Navigator.of(context).pop();
        case QueuedOutcome():
          showMessage(context, context.t('order_queued'), error: true);
          Navigator.of(context).pop();
        case RefusedOutcome(:final error):
          await showDialog<void>(
            context: context,
            builder: (c) => AlertDialog(
              title: Text(c.t('status_failed')),
              content: Text(error.message),
              actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(c.t('close')))],
            ),
          );
          floor.refresh();
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _openReview(Money money) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => CartSheet(
        target: widget.target,
        existing: _existing,
        isAddRound: _openOrder != null,
        money: money,
        onSend: () {
          Navigator.pop(context);
          _send();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final menuRepo = context.watch<MenuRepository>();
    final carts = context.watch<CartStore>();
    final outbox = context.watch<Outbox>();
    final menu = menuRepo.data;
    final money = menuRepo.money;
    final cart = carts.cartFor(widget.target.key);
    final waitingHere = outbox.forCart(widget.target.key);
    final ar = context.isArabic;
    final title = widget.target.takeaway ? context.t('takeaway') : (widget.target.tableLabel ?? widget.target.table!);
    final floor = context.watch<FloorController>();
    final openOrder = widget.target.takeaway ? null : (floor.live(widget.target.table!)?.order?.order ?? widget.openOrder);

    final items = menu == null
        ? const <MenuItem>[]
        : menu.items.where((i) {
            if (_query.isNotEmpty) {
              final q = normalizeForSearch(_query);
              return normalizeForSearch('${i.itemName} ${i.itemNameAr ?? ''} ${i.itemCode}').contains(q);
            }
            return _group == null || i.itemGroup == _group;
          }).toList();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title),
          Text(
            [
              if (widget.target.room != null) widget.target.room!,
              ?openOrder,
              if (_existing != null) money.withCode(_existing!.total),
            ].join(' · '),
            style: const TextStyle(fontFamily: Nami.bodyFont, fontSize: 12, fontWeight: FontWeight.w400, color: Nami.onDeepMuted),
          ),
        ]),
        actions: [
          if (!cart.isEmpty)
            IconButton(
              tooltip: context.t('order_clear'),
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                if (await confirmDialog(context, title: context.t('order_clear_q'), confirm: context.t('remove'), destructive: true)) {
                  carts.clear(widget.target.key);
                }
              },
            ),
        ],
      ),
      body: menu == null
          ? EmptyState(
              icon: Icons.restaurant_menu,
              text: context.t('order_menu_missing'),
              action: OutlinedButton(onPressed: () => menuRepo.refresh(force: true), child: Text(context.t('retry'))),
            )
          : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _CategoryRail(
                groups: menu.groups,
                selected: _query.isEmpty ? _group : null,
                onSelect: (g) => setState(() {
                  _group = g;
                  _query = '';
                  _search.clear();
                  FocusScope.of(context).unfocus();
                }),
              ),
              Expanded(
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                    child: TextField(
                      key: const Key('menu_search'),
                      controller: _search,
                      onChanged: (v) => setState(() => _query = v.trim()),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: context.t('order_search'),
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => setState(() {
                                  _query = '';
                                  _search.clear();
                                }),
                              ),
                      ),
                    ),
                  ),
                  if (waitingHere.isNotEmpty)
                    StatusStrip(
                      text: context.t('order_waiting_here', {'n': waitingHere.length}),
                      color: Nami.amber,
                      textColor: Nami.ink,
                      icon: Icons.schedule_send,
                    ),
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 200,
                        mainAxisExtent: 116,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final it = items[i];
                        final g = menu.groups.where((x) => x.name == it.itemGroup).firstOrNull;
                        return ItemTile(
                          item: it,
                          arabicFirst: ar,
                          price: money.amount(it.rate),
                          qtyInCart: cart.qtyOf(it.itemCode),
                          stripe: _parseColor(g?.color) ?? Nami.teal,
                          hasOptions: it.modifierGroups.isNotEmpty,
                          onTap: () => _tapItem(it, menu, money),
                        );
                      },
                    ),
                  ),
                ]),
              ),
            ]),
      bottomNavigationBar: _CartBar(
        cart: cart,
        money: money,
        sending: _sending,
        sentCount: _existing?.itemCount.round() ?? 0,
        loadingSent: _loadingExisting,
        isAddRound: openOrder != null,
        onReview: () => _openReview(money),
        onSend: cart.isEmpty ? null : _send,
      ),
    );
  }
}

Color? _parseColor(String? hex) {
  if (hex == null) return null;
  final h = hex.replaceAll('#', '');
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

class _CategoryRail extends StatelessWidget {
  const _CategoryRail({required this.groups, required this.selected, required this.onSelect});
  final List<ItemGroup> groups;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final ar = context.isArabic;
    Widget tile(String? key, String label, Color stripe) {
      final sel = selected == key;
      return Material(
        color: sel ? Nami.cream : Colors.transparent,
        child: InkWell(
          onTap: () => onSelect(key),
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 8, 8),
            decoration: BoxDecoration(
              border: BorderDirectional(
                start: BorderSide(color: sel ? Nami.amber : stripe.withValues(alpha: 0.0), width: 4),
                bottom: const BorderSide(color: Color(0x22FFFFFF)),
              ),
            ),
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              label,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, height: 1.2, fontWeight: FontWeight.w600, color: sel ? Nami.ink : Nami.white),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 96,
      color: Nami.rail,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          tile(null, context.t('order_all_items'), Nami.amber),
          for (final g in groups) tile(g.name, ar && g.nameAr != null ? g.nameAr! : g.name, _parseColor(g.color) ?? Nami.teal),
        ],
      ),
    );
  }
}

class ItemTile extends StatelessWidget {
  const ItemTile({
    super.key,
    required this.item,
    required this.arabicFirst,
    required this.price,
    required this.qtyInCart,
    required this.stripe,
    required this.hasOptions,
    required this.onTap,
  });
  final MenuItem item;
  final bool arabicFirst;
  final String price;
  final int qtyInCart;
  final Color stripe;
  final bool hasOptions;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = arabicFirst && item.itemNameAr != null ? item.itemNameAr! : item.itemName;
    final secondary = arabicFirst ? item.itemName : item.itemNameAr;
    final off = !item.isAvailable;
    return Opacity(
      opacity: off ? 0.45 : 1,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(Nami.radius),
        child: InkWell(
          key: Key('item_${item.itemCode}'),
          borderRadius: BorderRadius.circular(Nami.radius),
          onTap: off ? null : onTap,
          child: Container(
            decoration: BoxDecoration(
              color: Nami.white,
              borderRadius: BorderRadius.circular(Nami.radius),
              border: Border(top: BorderSide(color: stripe, width: 4)),
              boxShadow: Nami.cardShadow,
            ),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Stack(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: EdgeInsetsDirectional.only(end: qtyInCart > 0 ? 30 : 0),
                  child: Text(primary, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.2)),
                ),
                if (secondary != null && secondary.isNotEmpty)
                  Text(secondary, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: Nami.muted, height: 1.3)),
                const Spacer(),
                Row(children: [
                  Text(price, style: Nami.num(20)),
                  const SizedBox(width: 4),
                  const Spacer(),
                  if (off)
                    Flexible(
                      child: Text(context.t('order_unavailable'),
                          maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end,
                          style: const TextStyle(fontSize: 11, color: Nami.red, fontWeight: FontWeight.w700)),
                    )
                  else if (hasOptions)
                    const Icon(Icons.tune, size: 16, color: Nami.muted),
                ]),
              ]),
              if (qtyInCart > 0)
                PositionedDirectional(
                  top: 0,
                  end: 0,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 28),
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: Nami.amber, borderRadius: BorderRadius.circular(14)),
                    child: Text('$qtyInCart', style: Nami.num(18, color: Nami.ink)),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _CartBar extends StatelessWidget {
  const _CartBar({
    required this.cart,
    required this.money,
    required this.sending,
    required this.sentCount,
    required this.loadingSent,
    required this.isAddRound,
    required this.onReview,
    required this.onSend,
  });
  final TableCart cart;
  final Money money;
  final bool sending;
  final int sentCount;
  final bool loadingSent;
  final bool isAddRound;
  final VoidCallback onReview;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    final n = cart.itemCount;
    return Container(
      decoration: const BoxDecoration(color: Nami.deep),
      padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + MediaQuery.paddingOf(context).bottom),
      child: Row(children: [
        SizedBox(
          height: 56,
          child: OutlinedButton(
            key: const Key('cart_review'),
            onPressed: (n == 0 && sentCount == 0) ? null : onReview,
            style: OutlinedButton.styleFrom(
              foregroundColor: Nami.white,
              side: const BorderSide(color: Color(0xFF4E8292), width: 1.5),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(n == 0 ? '—' : '$n', style: Nami.num(22, color: Nami.white)),
              Text(context.t('order_review'), style: const TextStyle(fontSize: 12, color: Nami.onDeep)),
            ]),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 56,
            child: FilledButton(
              key: const Key('cart_send'),
              onPressed: sending ? null : onSend,
              child: sending
                  ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Nami.ink)),
                      const SizedBox(width: 10),
                      Text(context.t('order_sending')),
                    ])
                  : n == 0
                      ? Text(context.t('order_cart_empty'), style: const TextStyle(fontSize: 15))
                      : FittedBox(
                          child: Row(children: [
                            Text(isAddRound ? context.t('order_add_round') : context.t('order_send')),
                            const SizedBox(width: 10),
                            Text(money.amount(cart.total), style: Nami.num(24, color: Nami.ink)),
                          ]),
                        ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Review: sent rounds (read-only) above the new lines (editable).
class CartSheet extends StatelessWidget {
  const CartSheet({super.key, required this.target, required this.existing, required this.isAddRound, required this.money, required this.onSend});
  final CartTarget target;
  final Order? existing;
  final bool isAddRound;
  final Money money;
  final VoidCallback onSend;

  Future<void> _editNote(BuildContext context, CartStore carts, CartLine line) async {
    final ctrl = TextEditingController(text: line.note);
    final r = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(c.t('order_line_note')),
        content: TextField(controller: ctrl, autofocus: true, maxLines: 3, minLines: 1, textCapitalization: TextCapitalization.sentences),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(c.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: Text(c.t('done'))),
        ],
      ),
    );
    if (r != null) carts.setNote(target.key, line.id, r);
  }

  @override
  Widget build(BuildContext context) {
    final carts = context.watch<CartStore>();
    final cart = carts.cartFor(target.key);
    final ar = context.isArabic;
    final sent = existing?.items ?? const <OrderLine>[];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              if (sent.isNotEmpty) ...[
                SectionCap('${context.t('order_sent_items')} · ${existing!.name}', padding: const EdgeInsets.fromLTRB(16, 0, 16, 6)),
                for (final l in sent)
                  Opacity(
                    opacity: 0.6,
                    child: ListTile(
                      dense: true,
                      leading: Text(_q(l.qty), style: Nami.num(20)),
                      title: Text(l.itemName, style: const TextStyle(fontSize: 15)),
                      subtitle: l.modifiers.isEmpty && l.specialInstructions == null
                          ? null
                          : Text([for (final m in l.modifiers) m.name, ?l.specialInstructions].join(' · ')),
                      trailing: Text(money.amount(l.amount), style: Nami.num(18, weight: FontWeight.w600)),
                    ),
                  ),
                const Divider(),
              ],
              SectionCap(context.t('order_new_items')),
              if (cart.isEmpty)
                Padding(padding: const EdgeInsets.all(16), child: Text(context.t('order_cart_empty'), style: const TextStyle(color: Nami.muted))),
              for (final l in cart.lines)
                Container(
                  key: Key('line_${l.itemCode}'),
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
                  decoration: BoxDecoration(color: Nami.white, borderRadius: BorderRadius.circular(Nami.radius), boxShadow: Nami.cardShadow),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(ar && l.itemNameAr != null ? l.itemNameAr! : l.itemName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          if (l.modifiers.isNotEmpty)
                            Text(l.modifiers.map((m) => m.price == 0 ? m.name : '${m.name} +${money.amount(m.price)}').join(' · '),
                                style: const TextStyle(fontSize: 13, color: Nami.muted)),
                        ]),
                      ),
                      Text(money.amount(l.lineTotal), style: Nami.num(20)),
                    ]),
                    Row(children: [
                      Expanded(
                        child: TextButton.icon(
                          style: TextButton.styleFrom(alignment: AlignmentDirectional.centerStart, padding: EdgeInsets.zero),
                          onPressed: () => _editNote(context, carts, l),
                          icon: const Icon(Icons.edit_note, size: 22),
                          label: Text(
                            l.note.isEmpty ? context.t('order_line_note') : l.note,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, color: l.note.isEmpty ? Nami.teal : Nami.ink, fontWeight: l.note.isEmpty ? FontWeight.w600 : FontWeight.w400),
                          ),
                        ),
                      ),
                      QtyStepper(value: l.qty, dense: true, onChanged: (v) => carts.setQty(target.key, l.id, v)),
                    ]),
                  ]),
                ),
              if (!isAddRound) ...[
                if (!target.takeaway)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
                    child: Row(children: [
                      const Icon(Icons.people_outline, color: Nami.muted),
                      const SizedBox(width: 10),
                      Expanded(child: Text(context.t('order_guests'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                      QtyStepper(value: cart.guests, onChanged: (v) => carts.setGuests(target.key, v)),
                    ]),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextFormField(
                    initialValue: cart.notes,
                    onChanged: (v) => carts.setNotes(target.key, v),
                    maxLines: 3,
                    minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(labelText: context.t('order_notes'), prefixIcon: const Icon(Icons.sticky_note_2_outlined)),
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ]),
          ),
          Container(
            decoration: const BoxDecoration(color: Nami.white, border: Border(top: BorderSide(color: Nami.line))),
            padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + MediaQuery.paddingOf(context).bottom),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: FilledButton(
                key: const Key('sheet_send'),
                onPressed: cart.isEmpty ? null : onSend,
                child: Text('${isAddRound ? context.t('order_add_round') : context.t('order_send')} · ${money.withCode(cart.total)}'),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  static String _q(double q) => q == q.roundToDouble() ? '${q.toInt()}' : '$q';
}
