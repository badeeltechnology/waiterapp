import '../../core/models/menu.dart';

enum ModifierError { requiredMissing, tooMany }

class GroupProblem {
  const GroupProblem(this.group, this.error);
  final ModifierGroup group;
  final ModifierError error;
}

/// The waiter's choices in the modifier sheet: group name -> chosen modifier names
/// (in tap order).
class ModifierSelection {
  ModifierSelection(this.groups, [Map<String, List<String>>? chosen]) : chosen = chosen ?? {};

  /// Starts with each group's defaults. A Single group keeps only its first default;
  /// a Multiple group keeps defaults up to its max.
  factory ModifierSelection.withDefaults(List<ModifierGroup> groups) {
    final chosen = <String, List<String>>{};
    for (final g in groups) {
      final defaults = g.modifiers.where((m) => m.isDefault).map((m) => m.name).toList();
      final max = g.maxAllowed;
      chosen[g.name] = max > 0 && defaults.length > max ? defaults.sublist(0, max) : defaults;
    }
    return ModifierSelection(groups, chosen);
  }

  final List<ModifierGroup> groups;
  final Map<String, List<String>> chosen;

  bool isChosen(String group, String modifier) => chosen[group]?.contains(modifier) ?? false;

  /// Taps a modifier. Single groups swap the choice (tapping the chosen one
  /// clears it unless the group is required). Multiple groups toggle, and refuse
  /// a new choice once the max is reached. Returns false when refused.
  bool toggle(ModifierGroup g, String modifier) {
    final list = chosen.putIfAbsent(g.name, () => []);
    if (list.contains(modifier)) {
      if (g.isSingle && g.isRequired) return true; // keep a required single choice
      list.remove(modifier);
      return true;
    }
    if (g.isSingle) {
      list
        ..clear()
        ..add(modifier);
      return true;
    }
    if (g.maxAllowed > 0 && list.length >= g.maxAllowed) return false;
    list.add(modifier);
    return true;
  }

  ModifierError? validateGroup(ModifierGroup g) {
    final n = chosen[g.name]?.length ?? 0;
    if (g.isRequired && n == 0) return ModifierError.requiredMissing;
    if (g.maxAllowed > 0 && n > g.maxAllowed) return ModifierError.tooMany;
    return null;
  }

  List<GroupProblem> problems() => [
        for (final g in groups)
          if (validateGroup(g) case final e?) GroupProblem(g, e),
      ];

  bool get isValid => problems().isEmpty;

  /// Chosen modifiers with prices, in group order.
  List<({String group, String name, double price})> resolved() => [
        for (final g in groups)
          for (final name in chosen[g.name] ?? const <String>[])
            (group: g.name, name: name, price: g.modifiers.firstWhere((m) => m.name == name, orElse: () => Modifier(name: name)).price),
      ];

  double get extraPrice => resolved().fold(0, (a, m) => a + m.price);
}
