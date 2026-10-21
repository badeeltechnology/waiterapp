import 'package:flutter/foundation.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/waiter_api.dart';
import '../../core/format.dart';
import '../../core/models/menu.dart';
import '../../core/storage.dart';

/// The bootstrap payload (menu, modifiers, floor plan), cached on the phone so
/// ordering works offline. Refreshes with the version check from the contract.
class MenuRepository extends ChangeNotifier {
  MenuRepository({required this.api, required this.store});
  final WaiterApi api;
  final JsonStore store;

  MenuData? data;
  String? profile;
  DateTime? updatedAt;
  bool loading = false;
  ApiException? error;

  Money get money => Money(currency: data?.currency ?? 'QAR', precision: data?.currencyPrecision ?? 2);

  String _key(String p) => 'menu_${p.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}';

  Future<void> open(String posProfile) async {
    if (profile != posProfile) {
      profile = posProfile;
      data = null;
      updatedAt = null;
      final raw = await store.load(_key(posProfile));
      if (raw is Map) {
        try {
          data = MenuData.fromJson(Map<String, dynamic>.from(raw['data'] as Map));
          updatedAt = DateTime.tryParse('${raw['updated_at']}');
        } catch (_) {
          data = null;
        }
      }
      notifyListeners();
    }
    await refresh();
  }

  Future<void> refresh({bool force = false}) async {
    final p = profile;
    if (p == null || loading) return;
    loading = true;
    notifyListeners();
    try {
      final r = await api.bootstrap(p, version: force ? null : data?.version);
      if (!r.unchanged && r.data != null) {
        data = r.data;
      }
      updatedAt = ServerClock.now();
      error = null;
      if (data != null) {
        await store.save(_key(p), {'updated_at': updatedAt!.toIso8601String(), 'data': data!.toJson()});
      }
    } on ApiException catch (e) {
      error = e;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  MenuItem? item(String code) => data?.items.where((i) => i.itemCode == code).firstOrNull;

  Future<void> wipe() async {
    final p = profile;
    data = null;
    profile = null;
    updatedAt = null;
    if (p != null) await store.save(_key(p), null);
    notifyListeners();
  }
}
