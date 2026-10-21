import 'package:flutter_test/flutter_test.dart';
import 'package:servepos_waiter/core/format.dart';
import 'package:servepos_waiter/core/i18n.dart';
import 'package:servepos_waiter/core/models/order.dart';

import 'support/fakes.dart';

void main() {
  group('OrderStatus mapping', () {
    test('contract values', () {
      expect(OrderStatus.parse('Pending'), OrderStatus.pending);
      expect(OrderStatus.parse('Accepted'), OrderStatus.accepted);
      expect(OrderStatus.parse('In Kitchen'), OrderStatus.inKitchen);
      expect(OrderStatus.parse('Ready'), OrderStatus.ready);
      expect(OrderStatus.parse('Served'), OrderStatus.served);
      expect(OrderStatus.parse('Paid'), OrderStatus.paid);
      expect(OrderStatus.parse('Cancelled'), OrderStatus.cancelled);
    });

    test('tolerant spellings', () {
      expect(OrderStatus.parse('in_kitchen'), OrderStatus.inKitchen);
      expect(OrderStatus.parse('IN KITCHEN'), OrderStatus.inKitchen);
      expect(OrderStatus.parse('Canceled'), OrderStatus.cancelled);
      expect(OrderStatus.parse('Rejected'), OrderStatus.rejected);
      expect(OrderStatus.parse('something new'), OrderStatus.unknown);
      expect(OrderStatus.parse(null), OrderStatus.unknown);
    });

    test('open / final', () {
      expect(OrderStatus.ready.isOpen, isTrue);
      expect(OrderStatus.paid.isOpen, isFalse);
      expect(OrderStatus.cancelled.isFinal, isTrue);
    });

    test('every status has EN and AR labels', () {
      for (final s in OrderStatus.values) {
        expect(hasTranslation(s.labelKey, 'en'), isTrue, reason: s.labelKey);
        expect(hasTranslation(s.labelKey, 'ar'), isTrue, reason: s.labelKey);
      }
    });
  });

  test('all strings have Arabic', () {
    for (final k in allStringKeys) {
      expect(hasTranslation(k, 'ar'), isTrue, reason: k);
    }
  });

  group('parsing', () {
    test('order shape', () {
      final o = Order.fromJson(orderJson());
      expect(o.items.first.modifiers.single.name, 'Oat milk');
      expect(o.itemCount, 3);
      expect(o.created, isNotNull);
    });

    test('tables: nested or flattened open-order summary', () {
      final nested = TableLive.fromJson(sampleTables()[1]);
      expect(nested.state, TableState.occupied);
      expect(nested.order!.order, 'WO-2026-00119');
      expect(nested.order!.status, OrderStatus.inKitchen);
      final flat = TableLive.fromJson({
        'name': 'T7', 'status': 'Occupied', 'order': 'WO-9', 'waiter': 'Sara', 'guests': 2, 'total': 50, 'order_status': 'Ready',
      });
      expect(flat.order!.order, 'WO-9');
      expect(flat.order!.waiter, 'Sara');
      expect(flat.order!.status, OrderStatus.ready);
    });

    test('menu round trip keeps modifiers', () {
      final m = sampleMenu();
      final again = sampleMenu().toJson();
      expect(again['modifier_groups'], hasLength(2));
      expect(m.groupsFor(m.items.first).map((g) => g.name), ['Milk', 'Extras']);
      expect(m.modifierGroups['Milk']!.isSingle, isTrue);
    });
  });

  group('search normalisation', () {
    test('Arabic alef and diacritics', () {
      expect(normalizeForSearch('إسبريسو'), normalizeForSearch('اسبريسو'));
      expect(normalizeForSearch('قَهْوَة'), normalizeForSearch('قهوه'));
      expect(normalizeForSearch('Iced  LATTE'), 'iced latte');
    });
  });

  test('money', () {
    final m = Money(currency: 'QAR', precision: 2);
    expect(m.amount(1234.5), '1,234.50');
    expect(m.withCode(28), 'QAR 28.00');
    expect(Money(precision: 3).amount(1), '1.000');
  });
}
