import 'package:flutter/material.dart';
import '../models/models.dart';

class ModifierSheet extends StatefulWidget {
  final MenuItem item;
  final List<ModifierGroup> modifierGroups;

  const ModifierSheet({super.key, required this.item, required this.modifierGroups});

  @override
  State<ModifierSheet> createState() => _ModifierSheetState();
}

class _ModifierSheetState extends State<ModifierSheet> {
  final Map<String, List<Modifier>> _selections = {};
  final _instructionsController = TextEditingController();
  int _qty = 1;

  @override
  void initState() {
    super.initState();
    // Pre-select defaults
    for (final group in widget.modifierGroups) {
      _selections[group.groupName] = [];
      for (final mod in group.modifiers) {
        if (mod.isDefault) {
          _selections[group.groupName]!.add(mod);
        }
      }
    }
  }

  @override
  void dispose() {
    _instructionsController.dispose();
    super.dispose();
  }

  bool get _isValid {
    for (final group in widget.modifierGroups) {
      if (group.isRequired && (_selections[group.groupName]?.isEmpty ?? true)) {
        return false;
      }
    }
    return true;
  }

  double get _modifierTotal {
    double total = 0;
    for (final mods in _selections.values) {
      for (final mod in mods) {
        total += mod.price;
      }
    }
    return total;
  }

  void _toggleModifier(ModifierGroup group, Modifier mod) {
    setState(() {
      final list = _selections[group.groupName] ??= [];
      if (group.selectionType == 'Single') {
        list.clear();
        list.add(mod);
      } else {
        if (list.any((m) => m.name == mod.name)) {
          list.removeWhere((m) => m.name == mod.name);
        } else {
          if (group.maxSelections > 0 && list.length >= group.maxSelections) return;
          list.add(mod);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalAmount = (widget.item.rate + _modifierTotal) * _qty;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            ),

            // Item header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.item.itemName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    if (widget.item.itemNameAr != null)
                      Text(widget.item.itemNameAr!, style: TextStyle(fontSize: 14, color: Colors.grey[600]), textDirection: TextDirection.rtl),
                    Text('${widget.item.rate.toStringAsFixed(2)} QAR', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: theme.colorScheme.primary)),
                  ],
                )),
              ]),
            ),

            // Modifier groups
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  ...widget.modifierGroups.map((group) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(group.groupName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        if (group.isRequired)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(4)),
                            child: Text('Required', style: TextStyle(fontSize: 10, color: Colors.red[700], fontWeight: FontWeight.w600)),
                          ),
                        const Spacer(),
                        Text(
                          group.selectionType == 'Single' ? 'Pick one' : group.maxSelections > 0 ? 'Pick up to ${group.maxSelections}' : 'Pick any',
                          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      ...group.modifiers.map((mod) {
                        final isSelected = _selections[group.groupName]?.any((m) => m.name == mod.name) ?? false;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          leading: group.selectionType == 'Single'
                            ? Radio<bool>(value: true, groupValue: isSelected ? true : null, onChanged: (_) => _toggleModifier(group, mod))
                            : Checkbox(value: isSelected, onChanged: (_) => _toggleModifier(group, mod)),
                          title: Text(mod.name, style: const TextStyle(fontSize: 14)),
                          trailing: mod.price > 0
                            ? Text('+${mod.price.toStringAsFixed(2)}', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w500))
                            : null,
                          onTap: () => _toggleModifier(group, mod),
                        );
                      }),
                      const Divider(height: 24),
                    ],
                  )),

                  // Special instructions
                  TextField(
                    controller: _instructionsController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Special instructions...',
                      filled: true,
                      fillColor: Colors.grey[50],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),

            // Bottom bar: qty + add button
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withAlpha(15), blurRadius: 10, offset: const Offset(0, -2))],
              ),
              child: SafeArea(
                child: Row(children: [
                  // Qty
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      IconButton(icon: const Icon(Icons.remove), onPressed: _qty > 1 ? () => setState(() => _qty--) : null, visualDensity: VisualDensity.compact),
                      Text('$_qty', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      IconButton(icon: const Icon(Icons.add), onPressed: () => setState(() => _qty++), visualDensity: VisualDensity.compact),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  // Add button
                  Expanded(
                    child: FilledButton(
                      onPressed: _isValid ? () {
                        final allMods = <Modifier>[];
                        for (final mods in _selections.values) allMods.addAll(mods);
                        final instructions = _instructionsController.text.trim();

                        Navigator.pop(context, CartItem(
                          itemCode: widget.item.itemCode,
                          itemName: widget.item.itemName,
                          itemNameAr: widget.item.itemNameAr,
                          rate: widget.item.rate,
                          qty: _qty,
                          modifiers: allMods,
                          modifierTotal: _modifierTotal,
                          specialInstructions: instructions.isEmpty ? null : instructions,
                        ));
                      } : null,
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                      child: Text('Add  -  ${totalAmount.toStringAsFixed(2)} QAR', style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
