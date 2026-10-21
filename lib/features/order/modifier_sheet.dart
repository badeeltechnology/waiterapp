import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/models/menu.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'cart.dart';
import 'modifier_selection.dart';

/// Options for one item. Honours Single/Multiple, required, max selections
/// and defaults. Returns the line to add, or null.
Future<CartLine?> showModifierSheet(BuildContext context, {required MenuItem item, required List<ModifierGroup> groups, required Money money}) {
  return showModalBottomSheet<CartLine>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ModifierSheet(item: item, groups: groups, money: money),
  );
}

class ModifierSheet extends StatefulWidget {
  const ModifierSheet({super.key, required this.item, required this.groups, required this.money});
  final MenuItem item;
  final List<ModifierGroup> groups;
  final Money money;

  @override
  State<ModifierSheet> createState() => _ModifierSheetState();
}

class _ModifierSheetState extends State<ModifierSheet> {
  late final ModifierSelection _sel = ModifierSelection.withDefaults(widget.groups);
  final _note = TextEditingController();
  int _qty = 1;
  bool _showErrors = false;
  String? _flash; // group name that refused a tap (max reached)

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _tap(ModifierGroup g, Modifier m) {
    HapticFeedback.selectionClick();
    setState(() {
      final ok = _sel.toggle(g, m.name);
      _flash = ok ? null : g.name;
    });
  }

  void _add() {
    if (!_sel.isValid) {
      HapticFeedback.heavyImpact();
      setState(() => _showErrors = true);
      return;
    }
    final mods = [for (final r in _sel.resolved()) CartModifier(group: r.group, name: r.name, price: r.price)];
    Navigator.pop(context, CartLine.fromItem(widget.item, modifiers: mods, qty: _qty, note: _note.text.trim()));
  }

  String _ruleText(ModifierGroup g) {
    final need = g.isRequired ? context.t('mod_required') : context.t('mod_optional');
    final pick = g.isSingle
        ? context.t('mod_pick_one')
        : (g.maxAllowed > 0 ? context.t('mod_pick_up_to', {'n': g.maxAllowed}) : context.t('mod_pick_any'));
    return '$need · $pick';
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final ar = context.isArabic;
    final primary = ar && item.itemNameAr != null ? item.itemNameAr! : item.itemName;
    final secondary = ar ? item.itemName : item.itemNameAr;
    final unit = item.rate + _sel.extraPrice;
    final problems = {for (final p in _sel.problems()) p.group.name: p.error};

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(primary, style: Nami.num(26)),
                  if (secondary != null && secondary.isNotEmpty)
                    Text(secondary, style: const TextStyle(fontSize: 15, color: Nami.muted)),
                ]),
              ),
              Text(widget.money.amount(item.rate), style: Nami.num(24, color: Nami.teal)),
            ]),
          ),
          const Divider(),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                for (final g in widget.groups) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                    child: Row(children: [
                      Expanded(child: Text(g.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
                      Pill(
                        label: _ruleText(g),
                        color: g.isRequired ? (_showErrors && problems.containsKey(g.name) ? Nami.red : Nami.deep) : Nami.line,
                        textColor: g.isRequired ? Nami.white : Nami.ink,
                      ),
                    ]),
                  ),
                  if (_showErrors && problems[g.name] != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                      child: Text(
                        problems[g.name] == ModifierError.requiredMissing
                            ? context.t('mod_err_required', {'g': g.name})
                            : context.t('mod_err_max', {'g': g.name, 'n': g.maxAllowed}),
                        style: const TextStyle(color: Nami.red, fontWeight: FontWeight.w600),
                      ),
                    ),
                  if (_flash == g.name)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                      child: Text(context.t('mod_err_max', {'g': g.name, 'n': g.maxAllowed}),
                          style: const TextStyle(color: Nami.amberText, fontWeight: FontWeight.w600)),
                    ),
                  for (final m in g.modifiers)
                    _OptionRow(
                      key: Key('mod_${g.name}_${m.name}'),
                      label: m.name,
                      price: m.price == 0 ? null : '+${widget.money.amount(m.price)}',
                      selected: _sel.isChosen(g.name, m.name),
                      radio: g.isSingle,
                      onTap: () => _tap(g, m),
                    ),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                  child: TextField(
                    controller: _note,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 2,
                    minLines: 1,
                    decoration: InputDecoration(labelText: context.t('order_line_note'), prefixIcon: const Icon(Icons.edit_note)),
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: const BoxDecoration(color: Nami.white, border: Border(top: BorderSide(color: Nami.line))),
            padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + MediaQuery.paddingOf(context).bottom),
            child: Row(children: [
              QtyStepper(value: _qty, min: 1, onChanged: (v) => setState(() => _qty = v)),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  key: const Key('mod_add'),
                  onPressed: _add,
                  child: FittedBox(
                    child: Text('${context.t('mod_add_to_order')} · ${widget.money.amount(unit * _qty)}'),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({super.key, required this.label, this.price, required this.selected, required this.radio, required this.onTap});
  final String label;
  final String? price;
  final bool selected;
  final bool radio;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final icon = radio
        ? (selected ? Icons.radio_button_checked : Icons.radio_button_unchecked)
        : (selected ? Icons.check_box : Icons.check_box_outline_blank);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: selected ? const Color(0xFFE3F0F3) : Nami.white,
        borderRadius: BorderRadius.circular(Nami.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(Nami.radius),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Nami.radius),
              border: Border.all(color: selected ? Nami.teal : Nami.line, width: selected ? 2 : 1),
            ),
            child: Row(children: [
              Icon(icon, color: selected ? Nami.teal : Nami.muted, size: 26),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: TextStyle(fontSize: 16, fontWeight: selected ? FontWeight.w600 : FontWeight.w400))),
              if (price != null) Text(price!, style: Nami.num(19, weight: FontWeight.w600, color: Nami.muted)),
            ]),
          ),
        ),
      ),
    );
  }
}
