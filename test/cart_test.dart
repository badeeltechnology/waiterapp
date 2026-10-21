import 'package:flutter_test/flutter_test.dart';
import 'package:servepos_waiter/core/storage.dart';
import 'package:servepos_waiter/features/order/cart.dart';

import 'support/fakes.dart';

void main() {
  final menu = sampleMenu();
  final latte = menu.items.firstWhere((i) => i.itemCode == 'LATTE');
  final fries = menu.items.firstWhere((i) => i.itemCode == 'FRIES');
  const t4 = CartTarget.table(table: 'T4');
  const t9 = CartTarget.table(table: 'T9');

  test('each table keeps its own draft (UX review High #5)', () {
    final s = CartStore();
    s.add(t4.key, CartLine.fromItem(fries));
    s.add(t4.key, CartLine.fromItem(latte, modifiers: const [CartModifier(group: 'Milk', name: 'Oat milk', price: 3)]));
    // Waiter walks to T9 and back.
    s.add(t9.key, CartLine.fromItem(fries, qty: 2));
    expect(s.cartFor(t4.key).itemCount, 2);
    expect(s.cartFor(t9.key).itemCount, 2);
    expect(s.cartFor(t4.key).lines.map((l) => l.itemCode), ['FRIES', 'LATTE']);
    expect(s.draftKeys, {t4.key, t9.key});
    s.clear(t9.key);
    expect(s.cartFor(t4.key).itemCount, 2, reason: 'clearing T9 never touches T4');
    expect(s.draftKeys, {t4.key});
  });

  test('identical lines merge; different modifiers or notes do not', () {
    final s = CartStore();
    s.add(t4.key, CartLine.fromItem(fries));
    s.add(t4.key, CartLine.fromItem(fries));
    expect(s.cartFor(t4.key).lines.length, 1);
    expect(s.cartFor(t4.key).lines.first.qty, 2);
    s.add(t4.key, CartLine.fromItem(fries, note: 'extra salt'));
    expect(s.cartFor(t4.key).lines.length, 2);
    s.add(t4.key, CartLine.fromItem(latte, modifiers: const [CartModifier(group: 'Milk', name: 'Oat milk', price: 3)]));
    s.add(t4.key, CartLine.fromItem(latte, modifiers: const [CartModifier(group: 'Milk', name: 'Almond milk', price: 3)]));
    expect(s.cartFor(t4.key).lines.length, 4);
  });

  test('totals include modifier prices; qty 0 removes the line', () {
    final s = CartStore();
    s.add(t4.key, CartLine.fromItem(latte, qty: 2, modifiers: const [CartModifier(group: 'Milk', name: 'Oat milk', price: 3)]));
    expect(s.cartFor(t4.key).total, 62);
    final id = s.cartFor(t4.key).lines.first.id;
    s.setQty(t4.key, id, 0);
    expect(s.cartFor(t4.key).isEmpty, isTrue);
  });

  test('payload carries modifiers by group/name and the note, never prices', () {
    final line = CartLine.fromItem(latte, modifiers: const [CartModifier(group: 'Milk', name: 'Oat milk', price: 3)], note: 'hot');
    expect(line.toPayload(), {
      'item_code': 'LATTE',
      'qty': 1,
      'modifiers': [
        {'group': 'Milk', 'name': 'Oat milk'},
      ],
      'special_instructions': 'hot',
    });
  });

  test('drafts persist across restarts', () async {
    final store = MemoryJsonStore();
    final a = CartStore(store: store);
    a.add(t4.key, CartLine.fromItem(fries, qty: 3));
    a.setGuests(t4.key, 4);
    a.setNotes(t4.key, 'birthday');
    await Future<void>.delayed(Duration.zero);
    final b = CartStore(store: store);
    await b.load();
    expect(b.cartFor(t4.key).itemCount, 3);
    expect(b.cartFor(t4.key).guests, 4);
    expect(b.cartFor(t4.key).notes, 'birthday');
  });

  test('takeaway is its own cart', () {
    const take = CartTarget.takeaway();
    expect(take.key, 'takeaway');
    expect(take.orderType, 'Takeaway');
    expect(t4.orderType, 'Dine In');
  });
}
