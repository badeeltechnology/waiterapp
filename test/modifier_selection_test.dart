import 'package:flutter_test/flutter_test.dart';
import 'package:servepos_waiter/core/models/menu.dart';
import 'package:servepos_waiter/features/order/modifier_selection.dart';

void main() {
  const milk = ModifierGroup(
    name: 'Milk',
    selectionType: 'Single',
    isRequired: true,
    maxSelections: 1,
    modifiers: [Modifier(name: 'Full cream'), Modifier(name: 'Oat milk', price: 3), Modifier(name: 'Almond milk', price: 3)],
  );
  const extras = ModifierGroup(
    name: 'Extras',
    selectionType: 'Multiple',
    maxSelections: 2,
    modifiers: [
      Modifier(name: 'Extra shot', price: 4, isDefault: true),
      Modifier(name: 'Vanilla', price: 2),
      Modifier(name: 'Caramel', price: 2),
    ],
  );
  const sauces = ModifierGroup(
    name: 'Sauces',
    selectionType: 'Multiple',
    isRequired: true,
    maxSelections: 0, // unlimited
    modifiers: [Modifier(name: 'Ketchup'), Modifier(name: 'Mayo'), Modifier(name: 'Chili'), Modifier(name: 'BBQ')],
  );

  test('required single group with no default is invalid until chosen', () {
    final s = ModifierSelection.withDefaults([milk]);
    expect(s.validateGroup(milk), ModifierError.requiredMissing);
    expect(s.isValid, isFalse);
    s.toggle(milk, 'Oat milk');
    expect(s.isValid, isTrue);
  });

  test('single group swaps; a required single choice cannot be cleared', () {
    final s = ModifierSelection.withDefaults([milk]);
    s.toggle(milk, 'Oat milk');
    s.toggle(milk, 'Almond milk');
    expect(s.chosen['Milk'], ['Almond milk']);
    s.toggle(milk, 'Almond milk');
    expect(s.chosen['Milk'], ['Almond milk']);
  });

  test('optional single can be cleared', () {
    const opt = ModifierGroup(name: 'Size', modifiers: [Modifier(name: 'Large')]);
    final s = ModifierSelection.withDefaults([opt]);
    s.toggle(opt, 'Large');
    s.toggle(opt, 'Large');
    expect(s.chosen['Size'], isEmpty);
    expect(s.isValid, isTrue);
  });

  test('defaults are preselected and count toward max', () {
    final s = ModifierSelection.withDefaults([extras]);
    expect(s.chosen['Extras'], ['Extra shot']);
    expect(s.toggle(extras, 'Vanilla'), isTrue);
    expect(s.toggle(extras, 'Caramel'), isFalse, reason: 'max 2 reached');
    expect(s.chosen['Extras'], ['Extra shot', 'Vanilla']);
    expect(s.extraPrice, 6);
  });

  test('too many defaults are trimmed to max', () {
    const g = ModifierGroup(
      name: 'G',
      selectionType: 'Multiple',
      maxSelections: 1,
      modifiers: [Modifier(name: 'a', isDefault: true), Modifier(name: 'b', isDefault: true)],
    );
    expect(ModifierSelection.withDefaults([g]).chosen['G'], ['a']);
    const single = ModifierGroup(name: 'S', modifiers: [Modifier(name: 'x', isDefault: true), Modifier(name: 'y', isDefault: true)]);
    expect(ModifierSelection.withDefaults([single]).chosen['S'], ['x']);
  });

  test('max 0 means unlimited; required multiple needs at least one', () {
    final s = ModifierSelection.withDefaults([sauces]);
    expect(s.validateGroup(sauces), ModifierError.requiredMissing);
    for (final m in sauces.modifiers) {
      expect(s.toggle(sauces, m.name), isTrue);
    }
    expect(s.isValid, isTrue);
  });

  test('tooMany is reported if data arrives over the limit', () {
    final s = ModifierSelection([extras], {'Extras': ['Extra shot', 'Vanilla', 'Caramel']});
    expect(s.validateGroup(extras), ModifierError.tooMany);
  });

  test('resolved keeps group order and prices', () {
    final s = ModifierSelection.withDefaults([milk, extras]);
    s.toggle(milk, 'Oat milk');
    expect(s.resolved().map((r) => '${r.group}/${r.name}/${r.price}'), ['Milk/Oat milk/3.0', 'Extras/Extra shot/4.0']);
  });
}
