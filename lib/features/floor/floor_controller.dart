import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/waiter_api.dart';
import '../../core/format.dart';
import '../../core/models/menu.dart';
import '../../core/models/order.dart';

/// Live floor. Keeps the last good answer when a refresh fails.
class FloorController extends ChangeNotifier {
  FloorController({required this.api});
  final WaiterApi api;

  String? profile;
  List<TableLive> tables = const [];
  DateTime? updatedAt;
  bool loading = false;
  ApiException? error;
  Timer? _timer;

  void open(String posProfile) {
    if (profile != posProfile) {
      profile = posProfile;
      tables = const [];
      updatedAt = null;
      error = null;
    }
    refresh();
  }

  Future<void> refresh() async {
    final p = profile;
    if (p == null || loading) return;
    loading = true;
    notifyListeners();
    try {
      tables = await api.tables(p);
      updatedAt = ServerClock.now();
      error = null;
    } on ApiException catch (e) {
      error = e;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Auto refresh while the floor is on screen and the app is in front.
  void setVisible(bool visible, {Duration every = const Duration(seconds: 15)}) {
    _visible = visible;
    _every = every;
    _timer?.cancel();
    _timer = null;
    if (visible) {
      _timer = Timer.periodic(every, (_) => refresh());
    }
  }

  bool _visible = false;
  Duration _every = const Duration(seconds: 15);

  /// App went to background: stop polling but remember whether the floor was on screen.
  void pause() {
    _timer?.cancel();
    _timer = null;
  }

  void resume() {
    if (_visible) setVisible(true, every: _every);
  }

  /// Shows a just-confirmed order on its table at once (the next refresh
  /// brings the server's view).
  void markOrder(Order o) {
    final t = o.table;
    if (t == null) return;
    final summary = TableOrderSummary(
      order: o.name,
      waiter: o.waiter,
      guests: o.guests,
      since: o.created,
      total: o.total,
      itemsCount: o.itemCount.round(),
      status: o.status,
    );
    final existing = live(t);
    final row = TableLive(
      name: t,
      tableName: existing?.tableName ?? t,
      room: existing?.room ?? o.room,
      capacity: existing?.capacity ?? 0,
      state: TableState.occupied,
      order: summary,
    );
    tables = existing == null ? [...tables, row] : [for (final x in tables) x.name == t ? row : x];
    notifyListeners();
  }

  TableLive? live(String table) => tables.where((t) => t.name == table).firstOrNull;

  /// Merges the floor plan from the menu cache with live status, so the floor
  /// still renders (as "unknown/free") when offline on first launch.
  List<TableLive> merged(List<TableDef> plan) {
    if (plan.isEmpty) return tables;
    final byName = {for (final t in tables) t.name: t};
    final out = <TableLive>[
      for (final d in plan)
        byName[d.name] ?? TableLive(name: d.name, tableName: d.tableName, room: d.room, capacity: d.capacity, state: TableState.available),
    ];
    // Tables the server knows but the cached plan does not (plan out of date).
    for (final t in tables) {
      if (!plan.any((d) => d.name == t.name)) out.add(t);
    }
    return out;
  }

  void clear() {
    setVisible(false);
    profile = null;
    tables = const [];
    updatedAt = null;
    error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
