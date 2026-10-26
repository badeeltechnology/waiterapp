import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/models/menu.dart';
import '../../core/models/order.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../auth/session_controller.dart';
import '../order/cart.dart';
import '../order/menu_repository.dart';
import '../order/outbox.dart';
import '../order/send_controller.dart';
import '../order/take_order_screen.dart';
import 'floor_controller.dart';

class FloorScreen extends StatefulWidget {
  const FloorScreen({super.key});
  @override
  State<FloorScreen> createState() => _FloorScreenState();
}

class _FloorScreenState extends State<FloorScreen> {
  String? _room; // null = all rooms

  Future<void> _find(BuildContext context, List<TableLive> all) async {
    final t = await showModalBottomSheet<TableLive>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FindTableSheet(tables: all),
    );
    if (t != null && context.mounted) {
      _open(
        context,
        CartTarget.table(table: t.name, room: t.room, tableLabel: t.tableName),
        live: t,
      );
    }
  }

  void _open(BuildContext context, CartTarget target, {TableLive? live}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TakeOrderScreen(target: target, openOrder: live?.order?.order),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final floor = context.watch<FloorController>();
    final menu = context.watch<MenuRepository>();
    final carts = context.watch<CartStore>();
    final outbox = context.watch<Outbox>();
    final sending = context.watch<SendController>();
    final session = context.watch<SessionController>();
    final money = menu.money;
    final plan = menu.data?.tables ?? const <TableDef>[];
    final rooms = menu.data?.rooms ?? const <Room>[];
    final all = floor.merged(plan);
    final roomNames = <String>{for (final r in rooms) r.name, for (final t in all) ?t.room}.toList();
    final shown = _room == null ? all : all.where((t) => t.room == _room).toList();
    final drafts = carts.draftKeys;
    TableBadge badgeFor(String key, TableLive t) {
      final entries = outbox.forCart(key);
      if (entries.any((e) => e.failed)) return TableBadge.notSent;
      if (sending.sendingFor(key) != null || entries.any((e) => outbox.isSending(e.id))) return TableBadge.sending;
      if (entries.isNotEmpty) return TableBadge.waiting;
      if (t.order?.status == OrderStatus.ready) return TableBadge.ready;
      if (sending.recentSentFor(key) != null) return TableBadge.sent;
      return TableBadge.none;
    }

    final now = ServerClock.now();

    String roomLabel(String name) => rooms.where((r) => r.name == name).firstOrNull?.roomName ?? name;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('floor_find'),
        heroTag: 'floor_find',
        backgroundColor: Nami.deep,
        foregroundColor: Nami.white,
        onPressed: () => _find(context, all),
        icon: const Icon(Icons.search, size: 26),
        label: Text(context.t('floor_find'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      appBar: AppBar(
        toolbarHeight: 64,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session.profile?.displayName ?? context.t('nav_floor')),
            Text(
              floor.updatedAt == null
                  ? (floor.error != null ? floor.error!.message : '')
                  : (floor.error != null ? context.t('floor_stale') : context.t('floor_updated', {'t': hhmm(floor.updatedAt!)})),
              style: TextStyle(
                fontFamily: Nami.bodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: floor.error != null ? Nami.amber : Nami.onDeepMuted,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: FilledButton.icon(
              key: const Key('floor_takeaway'),
              onPressed: () => _open(context, const CartTarget.takeaway()),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48), padding: const EdgeInsets.symmetric(horizontal: 14)),
              icon: const Icon(Icons.shopping_bag_outlined, size: 20),
              label: Text(context.t('floor_takeaway')),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (roomNames.length > 1)
            Container(
              color: Nami.rail,
              height: 64,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                children: [
                  _RoomChip(label: context.t('floor_all'), selected: _room == null, onTap: () => setState(() => _room = null)),
                  for (final r in roomNames) _RoomChip(label: roomLabel(r), selected: _room == r, onTap: () => setState(() => _room = r)),
                ],
              ),
            ),
          _Legend(all: shown),
          Expanded(
            child: RefreshIndicator(
              color: Nami.teal,
              onRefresh: () async {
                await Future.wait([floor.refresh(), menu.refresh()]);
              },
              child: shown.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: 320,
                          child: floor.loading || menu.loading
                              ? const Center(child: CircularProgressIndicator())
                              : EmptyState(
                                  icon: Icons.table_restaurant_outlined,
                                  text: menu.data == null ? context.t('order_menu_missing') : context.t('floor_empty'),
                                ),
                        ),
                      ],
                    )
                  : LayoutBuilder(
                      builder: (context, box) {
                        // Rows of equal-height tiles; height follows content so large
                        // system font sizes never clip.
                        const gap = 10.0;
                        // Three per row on a phone: a section of 20 fits in two screens.
                        final cols = ((box.maxWidth - 24 + gap) / (100 + gap)).floor().clamp(2, 8);
                        final rows = (shown.length / cols).ceil();
                        return ListView.builder(
                          // A new room starts at its first table, not at the old room's scroll offset.
                          key: ValueKey('floor_list_${_room ?? 'all'}'),
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
                          itemCount: rows,
                          itemBuilder: (context, r) => Padding(
                            padding: const EdgeInsets.only(bottom: gap),
                            child: IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (var c = 0; c < cols; c++) ...[
                                    if (c > 0) const SizedBox(width: gap),
                                    Expanded(
                                      child: r * cols + c < shown.length
                                          ? Builder(
                                              builder: (context) {
                                                final t = shown[r * cols + c];
                                                final key = CartTarget.table(table: t.name).key;
                                                return TableTile(
                                                  table: t,
                                                  money: money,
                                                  now: now,
                                                  hasDraft: drafts.contains(key),
                                                  badge: badgeFor(key, t),
                                                  sentAt: sending.recentSentFor(key)?.finishedAt,
                                                  onTap: () => _open(
                                                    context,
                                                    CartTarget.table(table: t.name, room: t.room, tableLabel: t.tableName),
                                                    live: t,
                                                  ),
                                                );
                                              },
                                            )
                                          : const SizedBox.shrink(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomChip extends StatelessWidget {
  const _RoomChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 8),
    child: Material(
      color: selected ? Nami.amber : Nami.deep,
      borderRadius: BorderRadius.circular(Nami.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(Nami.radius),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minWidth: 64, minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: selected ? Nami.ink : Nami.white),
          ),
        ),
      ),
    ),
  );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.all});
  final List<TableLive> all;

  @override
  Widget build(BuildContext context) {
    int n(TableState s) => all.where((t) => t.state == s).length;
    Widget dot(Color c, String label, int count) => Padding(
      padding: const EdgeInsetsDirectional.only(end: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(width: 6),
          Text(
            '$label $count',
            style: const TextStyle(fontSize: 13, color: Nami.muted, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Wrap(
        runSpacing: 4,
        children: [
          dot(Nami.white, context.t('floor_available'), n(TableState.available)),
          dot(Nami.teal, context.t('floor_occupied'), n(TableState.occupied)),
          dot(Nami.purple, context.t('floor_reserved'), n(TableState.reserved)),
        ],
      ),
    );
  }
}

enum TableBadge { none, notSent, sending, waiting, ready, sent }

/// Type a few characters of the table name; results sit right above the
/// keyboard, in thumb reach.
class FindTableSheet extends StatefulWidget {
  const FindTableSheet({super.key, required this.tables});
  final List<TableLive> tables;

  @override
  State<FindTableSheet> createState() => _FindTableSheetState();
}

class _FindTableSheetState extends State<FindTableSheet> {
  final _ctrl = TextEditingController();
  String get _q => _ctrl.text;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s\-_.]'), '');

  List<TableLive> get _matches {
    final q = _norm(_q);
    if (q.isEmpty) return const [];
    final hits = widget.tables.where((t) => _norm(t.tableName).contains(q) || _norm(t.name).contains(q)).toList();
    int rank(TableLive t) {
      final n = _norm(t.tableName);
      return n == q ? 0 : (n.startsWith(q) ? 1 : 2);
    }

    hits.sort((a, b) => rank(a).compareTo(rank(b)));
    return hits.take(12).toList();
  }

  @override
  Widget build(BuildContext context) {
    final m = _matches;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_q.isNotEmpty && m.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(context.t('floor_find_none'), style: const TextStyle(fontSize: 16, color: Nami.muted)),
            ),
          if (m.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in m)
                    SizedBox(
                      height: 56,
                      child: FilledButton(
                        key: Key('find_${t.name}'),
                        style: FilledButton.styleFrom(
                          backgroundColor: t.state == TableState.occupied ? Nami.teal : Nami.white,
                          foregroundColor: t.state == TableState.occupied ? Nami.white : Nami.ink,
                          side: const BorderSide(color: Nami.lineStrong),
                          minimumSize: const Size(88, 56),
                        ),
                        onPressed: () => Navigator.pop(context, t),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(t.tableName, style: Nami.num(24)),
                            if (t.room != null) Text(t.room!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: TextField(
              key: const Key('find_table_field'),
              controller: _ctrl,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textInputAction: TextInputAction.go,
              style: Nami.num(26),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (m.isNotEmpty) Navigator.pop(context, m.first);
              },
              decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: context.t('floor_find_hint')),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _badge(Widget pill) => Padding(
  padding: const EdgeInsets.only(top: 6),
  child: FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: pill),
);

class TableTile extends StatelessWidget {
  const TableTile({
    super.key,
    required this.table,
    required this.money,
    required this.now,
    required this.onTap,
    this.hasDraft = false,
    this.badge = TableBadge.none,
    this.sentAt,
  });
  final TableLive table;
  final Money money;
  final DateTime now;
  final VoidCallback onTap;
  final bool hasDraft;
  final TableBadge badge;
  final DateTime? sentAt;

  @override
  Widget build(BuildContext context) {
    final o = table.order;
    final occupied = table.state == TableState.occupied;
    final reserved = table.state == TableState.reserved;
    final bg = occupied ? Nami.teal : (reserved ? Nami.purple : Nami.white);
    final fg = occupied || reserved ? Nami.white : Nami.ink;
    final sub = occupied || reserved ? Nami.onDeep : Nami.muted;
    final ready = o?.status == OrderStatus.ready;

    return Semantics(
      button: true,
      label: 'Table ${table.tableName}',
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(Nami.radius),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(Nami.radius),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Nami.radius),
              border: ready ? Border.all(color: Nami.amber, width: 3) : (occupied || reserved ? null : Border.all(color: Nami.line, width: 1.5)),
            ),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            constraints: const BoxConstraints(minHeight: 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(table.tableName, maxLines: 1, style: Nami.num(30, color: fg)),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                const SizedBox(height: 8),
                if (occupied && o != null) ...[
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(money.amount(o.total), maxLines: 1, style: Nami.num(20, color: fg)),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          [
                            context.t('min', {'n': minutesSince(o.since, now)}),
                            ?o.waiter,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: sub),
                        ),
                      ),
                    ],
                  ),
                ] else
                  Text(
                    reserved
                        ? context.t('floor_reserved')
                        : (table.capacity > 0 ? '${context.t('floor_available')} · ${table.capacity}' : context.t('floor_available')),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: sub, fontWeight: FontWeight.w500),
                  ),
                // Send state first (most urgent), then the till's status, then a draft.
                switch (badge) {
                  TableBadge.notSent => _badge(Pill(label: context.t('status_failed'), color: Nami.red, icon: Icons.error_outline)),
                  TableBadge.sending => _badge(Pill(label: context.t('status_sending'), color: Nami.deep, icon: Icons.send)),
                  TableBadge.waiting => _badge(
                    Pill(label: context.t('status_waiting'), color: Nami.amber, textColor: Nami.ink, icon: Icons.schedule),
                  ),
                  TableBadge.ready => _badge(Pill(label: context.t('status_ready'), color: Nami.green, icon: Icons.room_service)),
                  TableBadge.sent => _badge(
                    Pill(
                      label: sentAt == null ? context.t('status_pending') : context.t('status_sent_at', {'t': hhmm(sentAt!)}),
                      color: Nami.green,
                      icon: Icons.check,
                    ),
                  ),
                  TableBadge.none =>
                    o != null && occupied && o.status != OrderStatus.unknown
                        ? _badge(Pill(label: context.t(o.status.labelKey), color: Nami.white, textColor: Nami.ink))
                        : const SizedBox.shrink(),
                },
                if (hasDraft)
                  _badge(
                    Pill(
                      label: context.t('floor_draft'),
                      color: occupied ? Nami.deep : Nami.cream,
                      textColor: occupied ? Nami.white : Nami.ink,
                      icon: Icons.edit,
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
