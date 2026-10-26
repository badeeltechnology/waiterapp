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
import 'outbox.dart';
import 'send_controller.dart';

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
  bool _asking = false; // "Send again?" is open

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

  /// One tap = one order. The controller is single-flight per table; this
  /// screen only asks "Send again?" for a likely duplicate and reacts to the result.
  Future<void> _send() async {
    final controller = context.read<SendController>();
    final key = widget.target.key;
    if (_asking || controller.sendingFor(key) != null) return;
    final carts = context.read<CartStore>();
    final cart = carts.cartFor(key);
    if (cart.isEmpty) return;
    final dup = controller.duplicateOf(key, SendController.signatureOf(cart));
    if (dup != null) {
      _asking = true;
      final again = await _askSendAgain(dup);
      _asking = false;
      if (!again || !mounted || controller.sendingFor(key) != null) return;
    }
    if (!mounted) return;
    final session = context.read<SessionController>();
    final floor = context.read<FloorController>();
    final job = await controller.submit(
      target: widget.target,
      posProfile: session.profile!.name,
      user: session.user!.user,
      existingOrder: _openOrder,
    );
    if (job.phase == SendPhase.sent) floor.refresh();
    if (!mounted) return;
    // Sent or safely queued: back to the floor (the result panel is on top).
    // Refused: stay, the panel offers Retry / Edit / Keep.
    if (job.phase != SendPhase.failed && (ModalRoute.of(context)?.isCurrent ?? false)) {
      Navigator.of(context).pop();
    }
  }

  Future<bool> _askSendAgain(DuplicateHit dup) async {
    final mins = DateTime.now().difference(dup.at).inMinutes;
    final r = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        key: const Key('dup_dialog'),
        icon: const Icon(Icons.content_copy, size: 36, color: Nami.amberText),
        title: Text(c.t('dup_title'), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dup.stillUnsent
                  ? c.t('dup_unsent', {'table': isolate(dup.label)})
                  : c.t(mins < 1 ? 'dup_sent_now' : 'dup_sent', {'table': isolate(dup.label), 'n': mins, 'order': isolate(dup.orderName ?? '')}),
              style: const TextStyle(fontSize: 17),
            ),
            const SizedBox(height: 10),
            Text(c.t('dup_hint'), style: const TextStyle(fontSize: 15, color: Nami.muted)),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          FilledButton(
            key: const Key('dup_cancel'),
            style: FilledButton.styleFrom(minimumSize: const Size(120, 52)),
            onPressed: () => Navigator.pop(c, false),
            child: Text(c.t('dup_cancel')),
          ),
          TextButton(
            key: const Key('dup_send'),
            style: TextButton.styleFrom(foregroundColor: Nami.red, minimumSize: const Size(48, 52)),
            onPressed: () => Navigator.pop(c, true),
            child: Text(c.t('dup_send')),
          ),
        ],
      ),
    );
    return r ?? false;
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
    final waitingHere = outbox.forCart(widget.target.key).where((e) => !outbox.isSending(e.id)).toList();
    final ar = context.isArabic;
    final title = widget.target.takeaway ? context.t('takeaway') : (widget.target.tableLabel ?? widget.target.table!);
    final floor = context.watch<FloorController>();
    final openOrder = widget.target.takeaway ? null : (floor.live(widget.target.table!)?.order?.order ?? widget.openOrder);

    final items = menu == null
        ? const <MenuItem>[]
        : (_query.isNotEmpty ? rankedSearch(menu.items, _query) : menu.items.where((i) => _group == null || i.itemGroup == _group).toList());
    final sendJob = context.watch<SendController>().sendingFor(widget.target.key);

    final scaffold = Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            Text(
              [if (widget.target.room != null) widget.target.room!, ?openOrder, if (_existing != null) money.withCode(_existing!.total)].join(' · '),
              style: const TextStyle(fontFamily: Nami.bodyFont, fontSize: 12, fontWeight: FontWeight.w400, color: Nami.onDeepMuted),
            ),
          ],
        ),
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
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                  child: Column(
                    children: [
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
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _CartBar(
        cart: cart,
        money: money,
        sending: sendJob != null,
        sendingCount: sendJob?.itemCount ?? 0,
        sentCount: _existing?.itemCount.round() ?? 0,
        loadingSent: _loadingExisting,
        isAddRound: openOrder != null,
        onReview: () => _openReview(money),
        onSend: cart.isEmpty ? null : _send,
      ),
    );
    if (sendJob == null) return scaffold;
    // Locked while sending: nothing can be added to or removed from what is on the wire.
    return Stack(
      children: [
        AbsorbPointer(child: scaffold),
        Positioned.fill(child: _SendingLock(job: sendJob)),
      ],
    );
  }
}

/// Menu search: exact and starts-with matches first, so "karak" finds "Karak"
/// before 25 "Karak Chai ..." variants.
List<MenuItem> rankedSearch(List<MenuItem> items, String query) {
  final q = normalizeForSearch(query);
  final scored = <(int, int, MenuItem)>[];
  for (var i = 0; i < items.length; i++) {
    final it = items[i];
    final en = normalizeForSearch(it.itemName);
    final ar = normalizeForSearch(it.itemNameAr ?? '');
    final code = it.itemCode.toLowerCase();
    int? rank;
    if (en == q || ar == q || code == q) {
      rank = 0;
    } else if (en.startsWith(q) || ar.startsWith(q)) {
      rank = 1;
    } else if (RegExp('(^|\\s)${RegExp.escape(q)}').hasMatch(en) || RegExp('(^|\\s)${RegExp.escape(q)}').hasMatch(ar)) {
      rank = 2;
    } else if ('$en $ar $code'.contains(q)) {
      rank = 3;
    }
    if (rank != null) scored.add((rank, i, it));
  }
  scored.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  return [for (final s in scored) s.$3];
}

class _SendingLock extends StatelessWidget {
  const _SendingLock({required this.job});
  final SendJob job;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('sending_lock'),
      color: const Color(0xF20B3B49),
      child: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 64,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 4),
                  child: IconButton(
                    key: const Key('lock_back'),
                    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                    iconSize: 28,
                    color: Nami.white,
                    icon: const BackButtonIcon(),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  children: [
                    const Spacer(),
                    const SizedBox(width: 72, height: 72, child: CircularProgressIndicator(strokeWidth: 6, color: Nami.amber)),
                    const SizedBox(height: 24),
                    Text(
                      context.t('send_sending_title'),
                      textAlign: TextAlign.center,
                      style: Nami.num(36, color: Nami.white),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.t('send_meta', {
                        'table': isolate([job.label, ?job.room].join(' · ')),
                        'n': isolate('${job.itemCount}'),
                        't': isolate(hhmm(job.startedAt)),
                      }),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, color: Nami.white, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      context.t('send_sending_body'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, color: Nami.onDeep, height: 1.35),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsetsDirectional.only(end: qtyInCart > 0 ? 30 : 0),
                      child: Text(
                        primary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.2),
                      ),
                    ),
                    if (secondary != null && secondary.isNotEmpty)
                      Text(
                        secondary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: Nami.muted, height: 1.3),
                      ),
                    const Spacer(),
                    Row(
                      children: [
                        Text(price, style: Nami.num(20)),
                        const SizedBox(width: 4),
                        const Spacer(),
                        if (off)
                          Flexible(
                            child: Text(
                              context.t('order_unavailable'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: const TextStyle(fontSize: 11, color: Nami.red, fontWeight: FontWeight.w700),
                            ),
                          )
                        else if (hasOptions)
                          const Icon(Icons.tune, size: 16, color: Nami.muted),
                      ],
                    ),
                  ],
                ),
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
              ],
            ),
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
    this.sendingCount = 0,
    required this.sentCount,
    required this.loadingSent,
    required this.isAddRound,
    required this.onReview,
    required this.onSend,
  });
  final TableCart cart;
  final Money money;
  final bool sending;
  final int sendingCount;
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
      child: Row(
        children: [
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(n == 0 ? '—' : '$n', style: Nami.num(22, color: Nami.white)),
                  Text(context.t('order_review'), style: const TextStyle(fontSize: 12, color: Nami.onDeep)),
                ],
              ),
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
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Nami.ink)),
                          const SizedBox(width: 10),
                          Text(context.t('order_sending'), style: const TextStyle(color: Nami.ink)),
                        ],
                      )
                    : n == 0
                    ? Text(context.t('order_cart_empty'), style: const TextStyle(fontSize: 15))
                    : FittedBox(
                        child: Row(
                          children: [
                            Text(isAddRound ? context.t('order_add_round') : context.t('order_send')),
                            const SizedBox(width: 10),
                            Text(money.amount(cart.total), style: Nami.num(24, color: Nami.ink)),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
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
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(context.t('order_cart_empty'), style: const TextStyle(color: Nami.muted)),
                    ),
                  for (final l in cart.lines)
                    Container(
                      key: Key('line_${l.itemCode}'),
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
                      decoration: BoxDecoration(color: Nami.white, borderRadius: BorderRadius.circular(Nami.radius), boxShadow: Nami.cardShadow),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      ar && l.itemNameAr != null ? l.itemNameAr! : l.itemName,
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                    ),
                                    if (l.modifiers.isNotEmpty)
                                      Text(
                                        l.modifiers.map((m) => m.price == 0 ? m.name : '${m.name} +${money.amount(m.price)}').join(' · '),
                                        style: const TextStyle(fontSize: 13, color: Nami.muted),
                                      ),
                                  ],
                                ),
                              ),
                              Text(money.amount(l.lineTotal), style: Nami.num(20)),
                            ],
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: TextButton.icon(
                                  style: TextButton.styleFrom(alignment: AlignmentDirectional.centerStart, padding: EdgeInsets.zero),
                                  onPressed: () => _editNote(context, carts, l),
                                  icon: const Icon(Icons.edit_note, size: 22),
                                  label: Text(
                                    l.note.isEmpty ? context.t('order_line_note') : l.note,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: l.note.isEmpty ? Nami.teal : Nami.ink,
                                      fontWeight: l.note.isEmpty ? FontWeight.w600 : FontWeight.w400,
                                    ),
                                  ),
                                ),
                              ),
                              QtyStepper(value: l.qty, dense: true, onChanged: (v) => carts.setQty(target.key, l.id, v)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  if (!isAddRound) ...[
                    if (!target.takeaway)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
                        child: Row(
                          children: [
                            const Icon(Icons.people_outline, color: Nami.muted),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(context.t('order_guests'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                            ),
                            QtyStepper(value: cart.guests, onChanged: (v) => carts.setGuests(target.key, v)),
                          ],
                        ),
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
                ],
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: Nami.white,
                border: Border(top: BorderSide(color: Nami.line)),
              ),
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
          ],
        ),
      ),
    );
  }

  static String _q(double q) => q == q.roundToDouble() ? '${q.toInt()}' : '$q';
}

Color? _parseColor(String? hex) {
  if (hex == null) return null;
  final h = hex.replaceAll('#', '');
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}
