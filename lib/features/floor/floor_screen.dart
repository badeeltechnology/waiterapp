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
import '../order/take_order_screen.dart';
import 'floor_controller.dart';

class FloorScreen extends StatefulWidget {
  const FloorScreen({super.key});
  @override
  State<FloorScreen> createState() => _FloorScreenState();
}

class _FloorScreenState extends State<FloorScreen> {
  String? _room; // null = all rooms

  void _open(BuildContext context, CartTarget target, {TableLive? live}) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TakeOrderScreen(target: target, openOrder: live?.order?.order),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final floor = context.watch<FloorController>();
    final menu = context.watch<MenuRepository>();
    final carts = context.watch<CartStore>();
    final outbox = context.watch<Outbox>();
    final session = context.watch<SessionController>();
    final money = menu.money;
    final plan = menu.data?.tables ?? const <TableDef>[];
    final rooms = menu.data?.rooms ?? const <Room>[];
    final all = floor.merged(plan);
    final roomNames = <String>{
      for (final r in rooms) r.name,
      for (final t in all) ?t.room,
    }.toList();
    final shown = _room == null ? all : all.where((t) => t.room == _room).toList();
    final drafts = carts.draftKeys;
    final waitingKeys = {for (final e in outbox.entries) e.cartKey};
    final now = ServerClock.now();

    String roomLabel(String name) => rooms.where((r) => r.name == name).firstOrNull?.roomName ?? name;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(session.profile?.displayName ?? context.t('nav_floor')),
          Text(
            floor.updatedAt == null
                ? (floor.error != null ? floor.error!.message : '')
                : (floor.error != null ? context.t('floor_stale') : context.t('floor_updated', {'t': hhmm(floor.updatedAt!)})),
            style: TextStyle(fontFamily: Nami.bodyFont, fontSize: 12, fontWeight: FontWeight.w400, color: floor.error != null ? Nami.amber : Nami.onDeepMuted),
          ),
        ]),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: FilledButton.icon(
              key: const Key('floor_takeaway'),
              onPressed: () => _open(context, const CartTarget.takeaway()),
              style: FilledButton.styleFrom(minimumSize: const Size(48, 44), padding: const EdgeInsets.symmetric(horizontal: 14)),
              icon: const Icon(Icons.shopping_bag_outlined, size: 20),
              label: Text(context.t('floor_takeaway')),
            ),
          ),
        ],
      ),
      body: Column(children: [
        if (roomNames.length > 1)
          Container(
            color: Nami.rail,
            height: 60,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              children: [
                _RoomChip(label: context.t('floor_all'), selected: _room == null, onTap: () => setState(() => _room = null)),
                for (final r in roomNames)
                  _RoomChip(label: roomLabel(r), selected: _room == r, onTap: () => setState(() => _room = r)),
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
                ? ListView(children: [
                    SizedBox(
                      height: 320,
                      child: floor.loading || menu.loading
                          ? const Center(child: CircularProgressIndicator())
                          : EmptyState(icon: Icons.table_restaurant_outlined, text: menu.data == null ? context.t('order_menu_missing') : context.t('floor_empty')),
                    ),
                  ])
                : LayoutBuilder(builder: (context, box) {
                    // Rows of equal-height tiles; height follows content so large
                    // system font sizes never clip.
                    const gap = 10.0;
                    final cols = ((box.maxWidth - 24 + gap) / (170 + gap)).floor().clamp(2, 8);
                    final rows = (shown.length / cols).ceil();
                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                      itemCount: rows,
                      itemBuilder: (context, r) => Padding(
                        padding: const EdgeInsets.only(bottom: gap),
                        child: IntrinsicHeight(
                          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            for (var c = 0; c < cols; c++) ...[
                              if (c > 0) const SizedBox(width: gap),
                              Expanded(
                                child: r * cols + c < shown.length
                                    ? Builder(builder: (context) {
                                        final t = shown[r * cols + c];
                                        final key = CartTarget.table(table: t.name).key;
                                        return TableTile(
                                          table: t,
                                          money: money,
                                          now: now,
                                          hasDraft: drafts.contains(key),
                                          waiting: waitingKeys.contains(key),
                                          onTap: () => _open(
                                            context,
                                            CartTarget.table(table: t.name, room: t.room, tableLabel: t.tableName),
                                            live: t,
                                          ),
                                        );
                                      })
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ]),
                        ),
                      ),
                    );
                  }),
          ),
        ),
      ]),
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
              constraints: const BoxConstraints(minWidth: 64, minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              child: Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: selected ? Nami.ink : Nami.white)),
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
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 6),
            Text('$label $count', style: const TextStyle(fontSize: 13, color: Nami.muted, fontWeight: FontWeight.w500)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Wrap(runSpacing: 4, children: [
        dot(Nami.white, context.t('floor_available'), n(TableState.available)),
        dot(Nami.teal, context.t('floor_occupied'), n(TableState.occupied)),
        dot(Nami.purple, context.t('floor_reserved'), n(TableState.reserved)),
      ]),
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
    this.waiting = false,
  });
  final TableLive table;
  final Money money;
  final DateTime now;
  final VoidCallback onTap;
  final bool hasDraft;
  final bool waiting;

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
              border: ready
                  ? Border.all(color: Nami.amber, width: 3)
                  : (occupied || reserved ? null : Border.all(color: Nami.line, width: 1.5)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            constraints: const BoxConstraints(minHeight: 118),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(table.tableName, maxLines: 1, overflow: TextOverflow.ellipsis, style: Nami.num(30, color: fg)),
                ),
                if (occupied && o != null)
                  Text(context.t('min', {'n': minutesSince(o.since, now)}), style: Nami.num(18, weight: FontWeight.w600, color: sub)),
              ]),
              const Spacer(),
              const SizedBox(height: 8),
              if (occupied && o != null) ...[
                Text(money.amount(o.total), style: Nami.num(22, color: fg)),
                const SizedBox(height: 2),
                Row(children: [
                  Expanded(
                    child: Text(
                      [o.waiter, if (o.guests > 0) '${o.guests} ${context.t('order_guests').toLowerCase()}'].whereType<String>().join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: sub),
                    ),
                  ),
                ]),
              ] else
                Text(
                  reserved
                      ? context.t('floor_reserved')
                      : (table.capacity > 0 ? '${context.t('floor_available')} · ${table.capacity}' : context.t('floor_available')),
                  style: TextStyle(fontSize: 14, color: sub, fontWeight: FontWeight.w500),
                ),
              // One badge, most urgent first, so the tile never overflows.
              if (waiting)
                _badge(Pill(label: context.t('status_waiting'), color: Nami.amber, textColor: Nami.ink, icon: Icons.schedule))
              else if (ready)
                _badge(Pill(label: context.t('status_ready'), color: Nami.amber, textColor: Nami.ink, icon: Icons.room_service))
              else if (hasDraft)
                _badge(Pill(label: context.t('floor_draft'), color: occupied ? Nami.deep : Nami.cream, textColor: occupied ? Nami.white : Nami.ink, icon: Icons.edit)),
            ]),
          ),
        ),
      ),
    );
  }
}
