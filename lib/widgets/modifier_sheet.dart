import 'package:flutter/material.dart';
import '../models/models.dart';

class ModifierSheet extends StatefulWidget {
  final MenuItem item;
  final List<ModifierGroup> modifierGroups;
  final CartItem? existingItem; // For edit mode

  const ModifierSheet({super.key, required this.item, required this.modifierGroups, this.existingItem});

  @override
  State<ModifierSheet> createState() => _ModifierSheetState();
}

class _ModifierSheetState extends State<ModifierSheet> {
  final Map<String, Set<String>> _selectedNames = {};
  final _instructionsController = TextEditingController();
  int _qty = 1;

  bool get _isEditMode => widget.existingItem != null;

  @override
  void initState() {
    super.initState();

    if (widget.existingItem != null) {
      // Edit mode — restore selections from existing cart item
      final existingModNames = widget.existingItem!.modifiers.map((m) => m.name).toSet();
      for (final group in widget.modifierGroups) {
        _selectedNames[group.groupName] = {};
        for (final mod in group.modifiers) {
          if (existingModNames.contains(mod.name)) {
            _selectedNames[group.groupName]!.add(mod.name);
          }
        }
      }
      _qty = widget.existingItem!.qty;
      if (widget.existingItem!.specialInstructions != null) {
        _instructionsController.text = widget.existingItem!.specialInstructions!;
      }
    } else {
      // New item — pre-select defaults
      for (final group in widget.modifierGroups) {
        _selectedNames[group.groupName] = {};
        for (final mod in group.modifiers) {
          if (mod.isDefault) {
            _selectedNames[group.groupName]!.add(mod.name);
          }
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
      if (group.isRequired && (_selectedNames[group.groupName]?.isEmpty ?? true)) {
        return false;
      }
    }
    return true;
  }

  double get _modifierTotal {
    double total = 0;
    for (final group in widget.modifierGroups) {
      final selected = _selectedNames[group.groupName] ?? {};
      for (final mod in group.modifiers) {
        if (selected.contains(mod.name)) {
          total += mod.price;
        }
      }
    }
    return total;
  }

  List<Modifier> get _allSelectedModifiers {
    final result = <Modifier>[];
    for (final group in widget.modifierGroups) {
      final selected = _selectedNames[group.groupName] ?? {};
      for (final mod in group.modifiers) {
        if (selected.contains(mod.name)) {
          result.add(mod);
        }
      }
    }
    return result;
  }

  void _onTapModifier(ModifierGroup group, Modifier mod) {
    setState(() {
      final selected = _selectedNames[group.groupName] ??= {};
      if (group.selectionType == 'Single') {
        // Single select — replace
        selected.clear();
        selected.add(mod.name);
      } else {
        // Multiple select — toggle
        if (selected.contains(mod.name)) {
          selected.remove(mod.name);
        } else {
          // Check max selections
          if (group.maxSelections > 0 && selected.length >= group.maxSelections) {
            return;
          }
          selected.add(mod.name);
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
        initialChildSize: 0.8,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            // Drag handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            ),

            // Item header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.item.itemName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    if (widget.item.itemNameAr != null)
                      Text(widget.item.itemNameAr!, style: TextStyle(fontSize: 14, color: Colors.grey[600]), textDirection: TextDirection.rtl),
                  ],
                )),
                Text('${widget.item.rate.toStringAsFixed(2)} QAR', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
              ]),
            ),

            const Divider(height: 1),

            // Modifier groups — scrollable
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.only(bottom: 16),
                children: [
                  ...widget.modifierGroups.map((group) => _ModifierGroupSection(
                    group: group,
                    selectedNames: _selectedNames[group.groupName] ?? {},
                    onTap: (mod) => _onTapModifier(group, mod),
                  )),

                  // Special instructions
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: TextField(
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
                  ),
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
                  // Qty controls
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
                        final instructions = _instructionsController.text.trim();
                        Navigator.pop(context, CartItem(
                          itemCode: widget.item.itemCode,
                          itemName: widget.item.itemName,
                          itemNameAr: widget.item.itemNameAr,
                          rate: widget.item.rate,
                          qty: _qty,
                          modifiers: _allSelectedModifiers,
                          modifierTotal: _modifierTotal,
                          specialInstructions: instructions.isEmpty ? null : instructions,
                        ));
                      } : null,
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                      child: Text('${_isEditMode ? 'Update' : 'Add'}  -  ${totalAmount.toStringAsFixed(2)} QAR', style: const TextStyle(fontWeight: FontWeight.w600)),
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

// Separate widget for each modifier group for clean layout
class _ModifierGroupSection extends StatelessWidget {
  final ModifierGroup group;
  final Set<String> selectedNames;
  final void Function(Modifier mod) onTap;

  const _ModifierGroupSection({
    required this.group,
    required this.selectedNames,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Group header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          color: Colors.grey[50],
          child: Row(children: [
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
              group.selectionType == 'Single'
                ? 'Pick one'
                : group.maxSelections > 0
                  ? 'Pick up to ${group.maxSelections}'
                  : 'Pick any',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ]),
        ),

        // Modifier options
        ...group.modifiers.map((mod) {
          final isSelected = selectedNames.contains(mod.name);

          return InkWell(
            onTap: () => onTap(mod),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Row(
                children: [
                  // Radio or Checkbox
                  if (group.selectionType == 'Single')
                    Radio<bool>(
                      value: true,
                      groupValue: isSelected ? true : null,
                      onChanged: (_) => onTap(mod),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    )
                  else
                    Checkbox(
                      value: isSelected,
                      onChanged: (_) => onTap(mod),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  const SizedBox(width: 4),
                  // Modifier name
                  Expanded(
                    child: Text(mod.name, style: TextStyle(fontSize: 14, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
                  ),
                  // Price
                  if (mod.price > 0)
                    Text('+${mod.price.toStringAsFixed(2)}', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w500, fontSize: 13)),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
