/// Bootstrap (menu + floor plan) shapes from `waiter.bootstrap`.
library;

double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
bool _b(Object? v, {bool dflt = false}) => v == null ? dflt : (v == true || v == 1 || v == '1');
String? _s(Object? v) => (v == null || '$v'.isEmpty) ? null : '$v';

class ItemGroup {
  const ItemGroup({required this.name, this.nameAr, this.sort = 0, this.color});
  final String name;
  final String? nameAr;
  final int sort;
  final String? color;

  factory ItemGroup.fromJson(Map<String, dynamic> j) =>
      ItemGroup(name: '${j['name']}', nameAr: _s(j['name_ar']), sort: _i(j['sort']), color: _s(j['color']));
  Map<String, dynamic> toJson() => {'name': name, 'name_ar': nameAr, 'sort': sort, 'color': color};
}

class MenuItem {
  const MenuItem({
    required this.itemCode,
    required this.itemName,
    this.itemNameAr,
    required this.itemGroup,
    required this.rate,
    this.image,
    this.description,
    this.isAvailable = true,
    this.modifierGroups = const [],
    this.sort = 0,
  });
  final String itemCode;
  final String itemName;
  final String? itemNameAr;
  final String itemGroup;
  final double rate;
  final String? image;
  final String? description;
  final bool isAvailable;
  final List<String> modifierGroups;
  final int sort;

  factory MenuItem.fromJson(Map<String, dynamic> j) => MenuItem(
        itemCode: '${j['item_code']}',
        itemName: '${j['item_name'] ?? j['item_code']}',
        itemNameAr: _s(j['item_name_ar']),
        itemGroup: '${j['item_group'] ?? ''}',
        rate: _d(j['rate']),
        image: _s(j['image']),
        description: _s(j['description']),
        isAvailable: _b(j['is_available'], dflt: true),
        modifierGroups: [for (final g in (j['modifier_groups'] as List? ?? const [])) '$g'],
        sort: _i(j['sort']),
      );
  Map<String, dynamic> toJson() => {
        'item_code': itemCode,
        'item_name': itemName,
        'item_name_ar': itemNameAr,
        'item_group': itemGroup,
        'rate': rate,
        'image': image,
        'description': description,
        'is_available': isAvailable,
        'modifier_groups': modifierGroups,
        'sort': sort,
      };
}

class Modifier {
  const Modifier({required this.name, this.price = 0, this.isDefault = false});
  final String name;
  final double price;
  final bool isDefault;
  factory Modifier.fromJson(Map<String, dynamic> j) =>
      Modifier(name: '${j['name']}', price: _d(j['price']), isDefault: _b(j['is_default']));
  Map<String, dynamic> toJson() => {'name': name, 'price': price, 'is_default': isDefault};
}

class ModifierGroup {
  const ModifierGroup({
    required this.name,
    this.selectionType = 'Single',
    this.isRequired = false,
    this.maxSelections = 0,
    this.modifiers = const [],
  });
  final String name;
  final String selectionType;
  final bool isRequired;

  /// 0 = no limit (only meaningful for Multiple).
  final int maxSelections;
  final List<Modifier> modifiers;

  bool get isSingle => selectionType.toLowerCase() == 'single';

  /// Effective upper bound: Single is always 1.
  int get maxAllowed => isSingle ? 1 : maxSelections;

  factory ModifierGroup.fromJson(Map<String, dynamic> j) => ModifierGroup(
        name: '${j['name']}',
        selectionType: '${j['selection_type'] ?? 'Single'}',
        isRequired: _b(j['is_required']),
        maxSelections: _i(j['max_selections']),
        modifiers: [
          for (final m in (j['modifiers'] as List? ?? const []))
            if (m is Map) Modifier.fromJson(Map<String, dynamic>.from(m)),
        ],
      );
  Map<String, dynamic> toJson() => {
        'name': name,
        'selection_type': selectionType,
        'is_required': isRequired,
        'max_selections': maxSelections,
        'modifiers': [for (final m in modifiers) m.toJson()],
      };
}

class Room {
  const Room({required this.name, required this.roomName});
  final String name;
  final String roomName;
  factory Room.fromJson(Map<String, dynamic> j) => Room(name: '${j['name']}', roomName: '${j['room_name'] ?? j['name']}');
  Map<String, dynamic> toJson() => {'name': name, 'room_name': roomName};
}

class TableDef {
  const TableDef({required this.name, required this.tableName, this.room, this.capacity = 0});
  final String name;
  final String tableName;
  final String? room;
  final int capacity;
  factory TableDef.fromJson(Map<String, dynamic> j) => TableDef(
        name: '${j['name']}',
        tableName: '${j['table_name'] ?? j['name']}',
        room: _s(j['room']),
        capacity: _i(j['capacity']),
      );
  Map<String, dynamic> toJson() => {'name': name, 'table_name': tableName, 'room': room, 'capacity': capacity};
}

class MenuSettings {
  const MenuSettings({this.orderStartTime, this.orderEndTime, this.allowCancelPending = true});
  final String? orderStartTime;
  final String? orderEndTime;
  final bool allowCancelPending;
  factory MenuSettings.fromJson(Map<String, dynamic> j) => MenuSettings(
        orderStartTime: _s(j['order_start_time']),
        orderEndTime: _s(j['order_end_time']),
        allowCancelPending: _b(j['allow_cancel_pending'], dflt: true),
      );
  Map<String, dynamic> toJson() =>
      {'order_start_time': orderStartTime, 'order_end_time': orderEndTime, 'allow_cancel_pending': allowCancelPending};
}

class MenuData {
  const MenuData({
    required this.version,
    this.currency = 'QAR',
    this.currencyPrecision = 2,
    this.settings = const MenuSettings(),
    this.groups = const [],
    this.items = const [],
    this.modifierGroups = const {},
    this.rooms = const [],
    this.tables = const [],
  });
  final String version;
  final String currency;
  final int currencyPrecision;
  final MenuSettings settings;
  final List<ItemGroup> groups;
  final List<MenuItem> items;
  final Map<String, ModifierGroup> modifierGroups;
  final List<Room> rooms;
  final List<TableDef> tables;

  List<ModifierGroup> groupsFor(MenuItem item) =>
      [for (final g in item.modifierGroups) if (modifierGroups[g] != null) modifierGroups[g]!];

  /// True if the item names a modifier group that is missing from the cache:
  /// such items must not be ordered (required options could be skipped).
  bool hasMissingGroups(MenuItem item) => item.modifierGroups.any((g) => !modifierGroups.containsKey(g));

  factory MenuData.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> list(String k) =>
        [for (final e in (j[k] as List? ?? const [])) if (e is Map) Map<String, dynamic>.from(e)];
    final groups = list('item_groups').map(ItemGroup.fromJson).toList()..sort((a, b) => a.sort.compareTo(b.sort));
    final items = list('items').map(MenuItem.fromJson).toList()..sort((a, b) => a.sort.compareTo(b.sort));
    return MenuData(
      version: '${j['version'] ?? ''}',
      currency: '${j['currency'] ?? 'QAR'}',
      currencyPrecision: j['currency_precision'] == null ? 2 : _i(j['currency_precision']),
      settings: j['settings'] is Map ? MenuSettings.fromJson(Map<String, dynamic>.from(j['settings'] as Map)) : const MenuSettings(),
      groups: groups,
      items: items,
      modifierGroups: {for (final g in list('modifier_groups').map(ModifierGroup.fromJson)) g.name: g},
      rooms: list('rooms').map(Room.fromJson).toList(),
      tables: list('tables').map(TableDef.fromJson).toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'currency': currency,
        'currency_precision': currencyPrecision,
        'settings': settings.toJson(),
        'item_groups': [for (final g in groups) g.toJson()],
        'items': [for (final i in items) i.toJson()],
        'modifier_groups': [for (final g in modifierGroups.values) g.toJson()],
        'rooms': [for (final r in rooms) r.toJson()],
        'tables': [for (final t in tables) t.toJson()],
      };
}
