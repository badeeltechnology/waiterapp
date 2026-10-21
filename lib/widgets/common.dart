import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/i18n.dart';
import '../core/models/order.dart';
import '../core/theme.dart';

/// White card on cream with the till's subtle shadow.
class NamiCard extends StatelessWidget {
  const NamiCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.onTap, this.color, this.border});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color ?? Nami.white,
        borderRadius: BorderRadius.circular(Nami.radius),
        boxShadow: Nami.cardShadow,
        border: border,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(Nami.radius),
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key, this.large = false});
  final OrderStatus status;
  final bool large;

  @override
  Widget build(BuildContext context) => Pill(
        label: context.t(status.labelKey),
        color: status.color,
        textColor: status.onColor,
        large: large,
      );
}

class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, required this.color, this.textColor = Nami.white, this.large = false, this.icon});
  final String label;
  final Color color;
  final Color textColor;
  final bool large;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 12 : 8, vertical: large ? 6 : 3),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: large ? 16 : 14, color: textColor), const SizedBox(width: 4)],
          Text(
            label,
            style: TextStyle(fontSize: large ? 14 : 12, fontWeight: FontWeight.w700, color: textColor, height: 1.2),
          ),
        ],
      ),
    );
  }
}

/// +/- with 48dp targets (UX review: steppers were 22-36dp).
class QtyStepper extends StatelessWidget {
  const QtyStepper({super.key, required this.value, required this.onChanged, this.min = 0, this.max = 999, this.dense = false});
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, bool enabled, int next, String semantic) => SizedBox(
          width: 48,
          height: 48,
          child: Semantics(
            button: true,
            label: semantic,
            child: Material(
              color: enabled ? Nami.cream : Nami.line.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(Nami.radius),
              child: InkWell(
                borderRadius: BorderRadius.circular(Nami.radius),
                onTap: enabled
                    ? () {
                        HapticFeedback.selectionClick();
                        onChanged(next);
                      }
                    : null,
                child: Icon(icon, size: 24, color: enabled ? Nami.ink : Nami.muted),
              ),
            ),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(value <= 1 && min == 0 ? Icons.delete_outline : Icons.remove, value > min, value - 1, 'minus'),
        SizedBox(
          width: dense ? 36 : 44,
          child: Text('$value', textAlign: TextAlign.center, style: Nami.num(24)),
        ),
        btn(Icons.add, value < max, value + 1, 'plus'),
      ],
    );
  }
}

class SectionCap extends StatelessWidget {
  const SectionCap(this.text, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(16, 18, 16, 8)});
  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(children: [
          Expanded(child: Text(context.isArabic ? text : text.toUpperCase(), style: Nami.cap)),
          ?trailing,
        ]),
      );
}

/// Full-width status strip under the app bar.
class StatusStrip extends StatelessWidget {
  const StatusStrip({super.key, required this.text, required this.color, this.textColor = Nami.white, this.icon, this.onTap});
  final String text;
  final Color color;
  final Color textColor;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              if (icon != null) ...[Icon(icon, size: 20, color: textColor), const SizedBox(width: 10)],
              Expanded(
                child: Text(text, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 14)),
              ),
              if (onTap != null) Icon(Icons.chevron_right, color: textColor),
            ]),
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: Nami.lineStrong),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Nami.muted)),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ]),
        ),
      );
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? body,
  required String confirm,
  bool destructive = false,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600)),
      content: body == null ? null : Text(body, style: const TextStyle(fontSize: 15)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(c.t('cancel'), style: const TextStyle(color: Nami.muted))),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: Nami.red, foregroundColor: Nami.white, minimumSize: const Size(48, 48)) : FilledButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () => Navigator.pop(c, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return r ?? false;
}

void showMessage(BuildContext context, String text, {bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  m?.hideCurrentSnackBar();
  m?.showSnackBar(SnackBar(
    content: Text(text),
    backgroundColor: error ? Nami.red : Nami.ink,
    duration: Duration(seconds: error ? 5 : 3),
  ));
}

/// Waiter initials disc, coloured per name like the till.
class WaiterDisc extends StatelessWidget {
  const WaiterDisc({super.key, required this.name, this.size = 28});
  final String name;
  final double size;
  static const _palette = [Color(0xFFC2662B), Color(0xFF7C5CBF), Color(0xFF0E6E86), Color(0xFFD9548A), Color(0xFF2E9E7A), Color(0xFF3F7FD1)];

  @override
  Widget build(BuildContext context) {
    final c = _palette[name.codeUnits.fold<int>(0, (a, b) => a + b) % _palette.length];
    final ini = name.trim().isEmpty ? '?' : String.fromCharCode(name.trim().runes.first).toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      child: Text(ini, style: Nami.num(size * 0.55, color: Nami.white)),
    );
  }
}
