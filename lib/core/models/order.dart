/// Order, floor and call shapes (WAITER_API_V2 "Order shape", tables, calls).
library;

import 'dart:ui' show Color;

import '../theme.dart';

double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
String? _s(Object? v) => (v == null || '$v'.isEmpty) ? null : '$v';

/// Frappe datetimes come as "YYYY-MM-DD HH:MM:SS[.ffffff]" in server local time.
DateTime? parseServerTime(Object? v) {
  if (v == null) return null;
  final s = '$v'.trim();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s.contains('T') ? s : s.replaceFirst(' ', 'T'));
}

enum OrderStatus {
  pending('Pending'),
  accepted('Accepted'),
  inKitchen('In Kitchen'),
  ready('Ready'),
  served('Served'),
  paid('Paid'),
  cancelled('Cancelled'),
  rejected('Rejected'),
  unknown('Unknown');

  const OrderStatus(this.wire);
  final String wire;

  static OrderStatus parse(Object? v) {
    final s = '${v ?? ''}'.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
    for (final st in OrderStatus.values) {
      if (st.wire.toLowerCase().replaceAll(' ', '') == s) return st;
    }
    if (s == 'kitchen' || s == 'preparing' || s == 'sent') return OrderStatus.inKitchen;
    if (s == 'completed' || s == 'closed') return OrderStatus.paid;
    if (s == 'canceled') return OrderStatus.cancelled;
    return OrderStatus.unknown;
  }

  /// Still on the floor (can receive more rounds).
  bool get isOpen => switch (this) {
        pending || accepted || inKitchen || ready || served => true,
        _ => false,
      };

  bool get isFinal => this == paid || this == cancelled || this == rejected;

  Color get color => switch (this) {
        pending => Nami.amber,
        accepted => Nami.teal,
        inKitchen => Nami.purple,
        ready => Nami.green,
        served => Nami.deep,
        paid => Nami.muted,
        cancelled || rejected => Nami.red,
        unknown => Nami.muted,
      };

  /// Text colour that passes contrast on [color].
  Color get onColor => this == pending ? Nami.ink : Nami.white;

  /// Key into the string table.
  String get labelKey => 'status_$name';
}

class OrderModifier {
  const OrderModifier({required this.group, required this.name, this.price = 0});
  final String group;
  final String name;
  final double price;
  factory OrderModifier.fromJson(Map<String, dynamic> j) =>
      OrderModifier(group: '${j['group'] ?? ''}', name: '${j['name'] ?? ''}', price: _d(j['price']));
}

class OrderLine {
  const OrderLine({
    required this.itemCode,
    required this.itemName,
    required this.qty,
    required this.rate,
    this.modifiers = const [],
    this.modifierTotal = 0,
    required this.amount,
    this.specialInstructions,
    this.round = 1,
    this.addedBy,
  });
  final String itemCode;
  final String itemName;
  final double qty;
  final double rate;
  final List<OrderModifier> modifiers;
  final double modifierTotal;
  final double amount;
  final String? specialInstructions;
  final int round;
  final String? addedBy;

  factory OrderLine.fromJson(Map<String, dynamic> j) => OrderLine(
        itemCode: '${j['item_code'] ?? ''}',
        itemName: '${j['item_name'] ?? j['item_code'] ?? ''}',
        qty: _d(j['qty']),
        rate: _d(j['rate']),
        modifiers: [
          for (final m in (j['modifiers'] as List? ?? const []))
            if (m is Map) OrderModifier.fromJson(Map<String, dynamic>.from(m)),
        ],
        modifierTotal: _d(j['modifier_total']),
        amount: _d(j['amount']),
        specialInstructions: _s(j['special_instructions']),
        round: j['round'] == null ? 1 : _i(j['round']),
        addedBy: _s(j['added_by']),
      );
}

class Order {
  const Order({
    required this.name,
    required this.status,
    this.posProfile,
    this.table,
    this.room,
    this.orderType = 'Dine In',
    this.guests = 0,
    this.waiter,
    this.created,
    this.modified,
    this.notes,
    this.total = 0,
    this.currency = 'QAR',
    this.items = const [],
  });
  final String name;
  final OrderStatus status;
  final String? posProfile;
  final String? table;
  final String? room;
  final String orderType;
  final int guests;
  final String? waiter;
  final DateTime? created;
  final DateTime? modified;
  final String? notes;
  final double total;
  final String currency;
  final List<OrderLine> items;

  bool get isTakeaway => orderType.toLowerCase() == 'takeaway';
  double get itemCount => items.fold(0, (a, l) => a + l.qty);
  int get rounds => items.fold(1, (a, l) => l.round > a ? l.round : a);

  factory Order.fromJson(Map<String, dynamic> j) => Order(
        name: '${j['name'] ?? ''}',
        status: OrderStatus.parse(j['status']),
        posProfile: _s(j['pos_profile']),
        table: _s(j['table']),
        room: _s(j['room']),
        orderType: '${j['order_type'] ?? 'Dine In'}',
        guests: _i(j['guests']),
        waiter: _s(j['waiter']),
        created: parseServerTime(j['created']),
        modified: parseServerTime(j['modified']),
        notes: _s(j['notes']),
        total: _d(j['total']),
        currency: '${j['currency'] ?? 'QAR'}',
        items: [
          for (final l in (j['items'] as List? ?? const []))
            if (l is Map) OrderLine.fromJson(Map<String, dynamic>.from(l)),
        ],
      );
}

enum TableState { available, occupied, reserved }

class TableOrderSummary {
  const TableOrderSummary({
    required this.order,
    this.waiter,
    this.guests = 0,
    this.since,
    this.total = 0,
    this.itemsCount = 0,
    this.status = OrderStatus.unknown,
  });
  final String order;
  final String? waiter;
  final int guests;
  final DateTime? since;
  final double total;
  final int itemsCount;
  final OrderStatus status;

  factory TableOrderSummary.fromJson(Map<String, dynamic> j) => TableOrderSummary(
        order: '${j['order'] ?? j['name'] ?? ''}',
        waiter: _s(j['waiter']),
        guests: _i(j['guests']),
        since: parseServerTime(j['since']),
        total: _d(j['total']),
        itemsCount: _i(j['items_count']),
        status: OrderStatus.parse(j['status']),
      );
}

class TableLive {
  const TableLive({required this.name, required this.tableName, this.room, this.capacity = 0, required this.state, this.order});
  final String name;
  final String tableName;
  final String? room;
  final int capacity;
  final TableState state;
  final TableOrderSummary? order;

  static TableState parseState(Object? v) => switch ('${v ?? ''}'.toLowerCase()) {
        'occupied' => TableState.occupied,
        'reserved' => TableState.reserved,
        _ => TableState.available,
      };

  /// Accepts the summary either nested (`order: {...}`) or flattened onto the
  /// table row (`order: "WO-..", waiter, guests, since, total...`).
  factory TableLive.fromJson(Map<String, dynamic> j) {
    TableOrderSummary? summary;
    final o = j['order'];
    if (o is Map) {
      summary = TableOrderSummary.fromJson(Map<String, dynamic>.from(o));
    } else if (o is String && o.isNotEmpty) {
      summary = TableOrderSummary.fromJson({...j, 'order': o, 'status': j['order_status'] ?? j['status']});
    } else if (j['open_order'] is Map) {
      summary = TableOrderSummary.fromJson(Map<String, dynamic>.from(j['open_order'] as Map));
    }
    var state = parseState(j['status']);
    if (summary != null && state == TableState.available) state = TableState.occupied;
    return TableLive(
      name: '${j['name'] ?? j['table'] ?? ''}',
      tableName: '${j['table_name'] ?? j['name'] ?? ''}',
      room: _s(j['room']),
      capacity: _i(j['capacity']),
      state: state,
      order: summary,
    );
  }
}

class GuestCall {
  const GuestCall({required this.name, this.table, this.room, this.created, this.status = 'Open', this.acceptedBy, this.guestNote});
  final String name;
  final String? table;
  final String? room;
  final DateTime? created;
  final String status;
  final String? acceptedBy;
  final String? guestNote;

  bool get isAccepted => acceptedBy != null && acceptedBy!.isNotEmpty;

  factory GuestCall.fromJson(Map<String, dynamic> j) => GuestCall(
        name: '${j['name']}',
        table: _s(j['table']),
        room: _s(j['room']),
        created: parseServerTime(j['created']),
        status: '${j['status'] ?? 'Open'}',
        acceptedBy: _s(j['accepted_by']),
        guestNote: _s(j['guest_note']),
      );
}
