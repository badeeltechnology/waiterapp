import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/models/menu.dart';
import '../../core/storage.dart';

class CartModifier {
  const CartModifier({required this.group, required this.name, this.price = 0});
  final String group;
  final String name;
  final double price;

  Map<String, dynamic> toJson() => {'group': group, 'name': name, 'price': price};
  factory CartModifier.fromJson(Map<String, dynamic> j) =>
      CartModifier(group: '${j['group']}', name: '${j['name']}', price: (j['price'] as num?)?.toDouble() ?? 0);

  @override
  bool operator ==(Object other) => other is CartModifier && other.group == group && other.name == name;
  @override
  int get hashCode => Object.hash(group, name);
}

class CartLine {
  CartLine({
    String? id,
    required this.itemCode,
    required this.itemName,
    this.itemNameAr,
    required this.rate,
    this.modifiers = const [],
    this.qty = 1,
    this.note = '',
  }) : id = id ?? const Uuid().v4();

  final String id;
  final String itemCode;
  final String itemName;
  final String? itemNameAr;

  /// Display only: the server prices the order.
  final double rate;
  final List<CartModifier> modifiers;
  int qty;
  String note;

  double get unitPrice => rate + modifiers.fold<double>(0, (a, m) => a + m.price);
  double get lineTotal => unitPrice * qty;

  /// Same item, same modifiers, no notes on either: the lines can merge.
  bool canMergeWith(CartLine o) =>
      o.itemCode == itemCode &&
      note.isEmpty &&
      o.note.isEmpty &&
      setEquals(o.modifiers.toSet(), modifiers.toSet());

  Map<String, dynamic> toPayload() => {
        'item_code': itemCode,
        'qty': qty,
        'modifiers': [for (final m in modifiers) {'group': m.group, 'name': m.name}],
        'special_instructions': note,
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'item_code': itemCode,
        'item_name': itemName,
        'item_name_ar': itemNameAr,
        'rate': rate,
        'modifiers': [for (final m in modifiers) m.toJson()],
        'qty': qty,
        'note': note,
      };

  factory CartLine.fromJson(Map<String, dynamic> j) => CartLine(
        id: j['id'] as String?,
        itemCode: '${j['item_code']}',
        itemName: '${j['item_name']}',
        itemNameAr: j['item_name_ar'] as String?,
        rate: (j['rate'] as num?)?.toDouble() ?? 0,
        modifiers: [for (final m in (j['modifiers'] as List? ?? const [])) CartModifier.fromJson(Map<String, dynamic>.from(m as Map))],
        qty: (j['qty'] as num?)?.toInt() ?? 1,
        note: (j['note'] ?? '') as String,
      );

  factory CartLine.fromItem(MenuItem item, {List<CartModifier> modifiers = const [], int qty = 1, String note = ''}) =>
      CartLine(
        itemCode: item.itemCode,
        itemName: item.itemName,
        itemNameAr: item.itemNameAr,
        rate: item.rate,
        modifiers: modifiers,
        qty: qty,
        note: note,
      );
}

/// Where a cart is headed. One per table plus one for takeaway.
class CartTarget {
  const CartTarget.table({required String this.table, this.room, this.tableLabel}) : takeaway = false;
  const CartTarget.takeaway()
      : table = null,
        room = null,
        tableLabel = null,
        takeaway = true;

  final String? table;
  final String? room;
  final String? tableLabel;
  final bool takeaway;

  String get key => takeaway ? 'takeaway' : 'table:$table';
  String get orderType => takeaway ? 'Takeaway' : 'Dine In';
}

class TableCart {
  TableCart({required this.key, List<CartLine>? lines, this.guests = 0, this.notes = ''}) : lines = lines ?? [];
  final String key;
  final List<CartLine> lines;
  int guests;
  String notes;

  bool get isEmpty => lines.isEmpty;
  int get itemCount => lines.fold(0, (a, l) => a + l.qty);
  double get total => lines.fold(0, (a, l) => a + l.lineTotal);
  int qtyOf(String itemCode) => lines.where((l) => l.itemCode == itemCode).fold(0, (a, l) => a + l.qty);

  List<Map<String, dynamic>> toPayloadItems() => [for (final l in lines) l.toPayload()];

  Map<String, dynamic> toJson() => {'key': key, 'guests': guests, 'notes': notes, 'lines': [for (final l in lines) l.toJson()]};
  factory TableCart.fromJson(Map<String, dynamic> j) => TableCart(
        key: '${j['key']}',
        guests: (j['guests'] as num?)?.toInt() ?? 0,
        notes: (j['notes'] ?? '') as String,
        lines: [for (final l in (j['lines'] as List? ?? const [])) CartLine.fromJson(Map<String, dynamic>.from(l as Map))],
      );
}

/// Keeps a separate draft per table, so switching tables never moves items
/// (UX review: "the cart is shared across tables"). Drafts survive app restarts.
class CartStore extends ChangeNotifier {
  CartStore({JsonStore? store, this.storeKey = 'carts'}) : _store = store;
  final JsonStore? _store;
  final String storeKey;
  final Map<String, TableCart> _carts = {};

  Future<void> load() async {
    final raw = await _store?.load(storeKey);
    _carts.clear();
    if (raw is List) {
      for (final c in raw) {
        if (c is Map) {
          final cart = TableCart.fromJson(Map<String, dynamic>.from(c));
          _carts[cart.key] = cart;
        }
      }
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    await _store?.save(storeKey, [for (final c in _carts.values) if (!c.isEmpty || c.guests > 0 || c.notes.isNotEmpty) c.toJson()]);
  }

  void _changed() {
    notifyListeners();
    _persist();
  }

  TableCart cartFor(String key) => _carts.putIfAbsent(key, () => TableCart(key: key));
  TableCart? peek(String key) => _carts[key];

  /// Keys of tables with unsent draft lines (floor shows a "Draft" badge).
  Set<String> get draftKeys => {for (final c in _carts.values) if (!c.isEmpty) c.key};

  void add(String key, CartLine line) {
    final cart = cartFor(key);
    final existing = cart.lines.where((l) => l.canMergeWith(line)).firstOrNull;
    if (existing != null) {
      existing.qty += line.qty;
    } else {
      cart.lines.add(line);
    }
    _changed();
  }

  void setQty(String key, String lineId, int qty) {
    final cart = cartFor(key);
    final line = cart.lines.where((l) => l.id == lineId).firstOrNull;
    if (line == null) return;
    if (qty <= 0) {
      cart.lines.remove(line);
    } else {
      line.qty = qty;
    }
    _changed();
  }

  void setNote(String key, String lineId, String note) {
    final line = cartFor(key).lines.where((l) => l.id == lineId).firstOrNull;
    if (line == null) return;
    line.note = note.trim();
    _changed();
  }

  void setGuests(String key, int guests) {
    cartFor(key).guests = guests < 0 ? 0 : guests;
    _changed();
  }

  void setNotes(String key, String notes) {
    cartFor(key).notes = notes;
    _changed();
  }

  void clear(String key) {
    _carts.remove(key);
    _changed();
  }

  /// Puts lines back into a draft (e.g. an order that the server refused).
  void restore(String key, List<CartLine> lines, {int? guests, String? notes}) {
    final cart = cartFor(key);
    for (final l in lines) {
      cart.lines.add(l);
    }
    if (guests != null && cart.guests == 0) cart.guests = guests;
    if (notes != null && cart.notes.isEmpty) cart.notes = notes;
    _changed();
  }

  Future<void> wipe() async {
    _carts.clear();
    notifyListeners();
    await _store?.save(storeKey, null);
  }
}
