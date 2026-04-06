import 'dart:convert';

// ==================== Data Models ====================

class ItemGroup {
  final String name;
  final String? parentGroup;
  final String? image;

  ItemGroup({required this.name, this.parentGroup, this.image});

  factory ItemGroup.fromJson(Map<String, dynamic> json) => ItemGroup(
    name: json['name'] ?? '',
    parentGroup: json['parent_item_group'],
    image: json['image'],
  );
}

class MenuItem {
  final String itemCode;
  final String itemName;
  final String? itemNameAr;
  final String? description;
  final String itemGroup;
  final double rate;
  final String? image;
  final bool hasVariants;

  MenuItem({
    required this.itemCode,
    required this.itemName,
    this.itemNameAr,
    this.description,
    required this.itemGroup,
    required this.rate,
    this.image,
    this.hasVariants = false,
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) => MenuItem(
    itemCode: json['name'] ?? '',
    itemName: json['item_name'] ?? '',
    itemNameAr: json['servepos_item_name_ar'],
    description: json['description'],
    itemGroup: json['item_group'] ?? '',
    rate: (json['standard_rate'] ?? 0).toDouble(),
    image: json['image'],
    hasVariants: json['has_variants'] == 1,
  );
}

class Modifier {
  final String name;
  final double price;
  final bool isDefault;

  Modifier({required this.name, required this.price, this.isDefault = false});

  factory Modifier.fromJson(Map<String, dynamic> json) => Modifier(
    name: json['name'] ?? json['modifier_name'] ?? '',
    price: (json['price'] ?? 0).toDouble(),
    isDefault: json['is_default'] == 1 || json['is_default'] == true,
  );

  Map<String, dynamic> toJson() => {'name': name, 'price': price};
}

class ModifierGroup {
  final String groupName;
  final String selectionType;
  final bool isRequired;
  final int maxSelections;
  final List<Modifier> modifiers;

  ModifierGroup({
    required this.groupName,
    required this.selectionType,
    required this.isRequired,
    required this.maxSelections,
    required this.modifiers,
  });

  factory ModifierGroup.fromJson(Map<String, dynamic> json) => ModifierGroup(
    groupName: json['group_name'] ?? '',
    selectionType: json['selection_type'] ?? 'Single',
    isRequired: json['is_required'] == 1,
    maxSelections: json['max_selections'] ?? 0,
    modifiers: (json['modifiers'] as List? ?? [])
        .map((m) => Modifier.fromJson(m))
        .toList(),
  );
}

class TableInfo {
  final String name;
  final String tableName;
  final String? room;
  final int capacity;
  final String status;
  final bool isActive;

  TableInfo({
    required this.name,
    required this.tableName,
    this.room,
    required this.capacity,
    required this.status,
    required this.isActive,
  });

  factory TableInfo.fromJson(Map<String, dynamic> json) => TableInfo(
    name: json['name'] ?? '',
    tableName: json['table_name'] ?? '',
    room: json['room'],
    capacity: json['capacity'] ?? 4,
    status: json['status'] ?? 'Available',
    isActive: json['is_active'] == 1,
  );
}

class Room {
  final String name;
  final String roomName;
  final bool isActive;

  Room({required this.name, required this.roomName, required this.isActive});

  factory Room.fromJson(Map<String, dynamic> json) => Room(
    name: json['name'] ?? '',
    roomName: json['room_name'] ?? '',
    isActive: json['is_active'] == 1,
  );
}

class CartItem {
  final String itemCode;
  final String itemName;
  final String? itemNameAr;
  final double rate;
  int qty;
  List<Modifier> modifiers;
  double modifierTotal;
  String? specialInstructions;

  CartItem({
    required this.itemCode,
    required this.itemName,
    this.itemNameAr,
    required this.rate,
    this.qty = 1,
    List<Modifier>? modifiers,
    this.modifierTotal = 0,
    this.specialInstructions,
  }) : modifiers = modifiers ?? [];

  double get amount => (rate + modifierTotal) * qty;

  Map<String, dynamic> toOrderItem() => {
    'item_code': itemCode,
    'item_name': itemName,
    'qty': qty,
    'rate': rate,
    'modifiers': modifiers.isNotEmpty
        ? jsonEncode(modifiers.map((m) => m.toJson()).toList())
        : null,
    'modifier_total': modifierTotal,
    'special_instructions': specialInstructions,
  };
}

class WaiterOrder {
  final String name;
  final String? waiter;
  final String? waiterName;
  final String? table;
  final String? room;
  final String orderType;
  final int guests;
  final String status;
  final String? notes;
  final String? editLog;
  final String? creation;
  final List<WaiterOrderItem> items;

  WaiterOrder({
    required this.name,
    this.waiter,
    this.waiterName,
    this.table,
    this.room,
    required this.orderType,
    required this.guests,
    required this.status,
    this.notes,
    this.editLog,
    this.creation,
    required this.items,
  });

  double get total => items.fold(0, (sum, i) => sum + i.amount);

  factory WaiterOrder.fromJson(Map<String, dynamic> json) => WaiterOrder(
    name: json['name'] ?? '',
    waiter: json['waiter'],
    waiterName: json['waiter_name'],
    table: json['table'],
    room: json['room'],
    orderType: json['order_type'] ?? 'Dine In',
    guests: json['guests'] ?? 1,
    status: json['status'] ?? 'Pending',
    notes: json['notes'],
    editLog: json['edit_log'],
    creation: json['creation'],
    items: (json['items'] as List? ?? [])
        .map((i) => WaiterOrderItem.fromJson(i))
        .toList(),
  );
}

class WaiterOrderItem {
  final String itemCode;
  final String itemName;
  final double qty;
  final double rate;
  final String? modifiers;
  final double modifierTotal;
  final String? specialInstructions;

  WaiterOrderItem({
    required this.itemCode,
    required this.itemName,
    required this.qty,
    required this.rate,
    this.modifiers,
    this.modifierTotal = 0,
    this.specialInstructions,
  });

  double get amount => (rate + modifierTotal) * qty;

  factory WaiterOrderItem.fromJson(Map<String, dynamic> json) => WaiterOrderItem(
    itemCode: json['item_code'] ?? '',
    itemName: json['item_name'] ?? '',
    qty: (json['qty'] ?? 1).toDouble(),
    rate: (json['rate'] ?? 0).toDouble(),
    modifiers: json['modifiers'],
    modifierTotal: (json['modifier_total'] ?? 0).toDouble(),
    specialInstructions: json['special_instructions'],
  );
}
