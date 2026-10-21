import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../order/menu_repository.dart';
import '../order/order_sender.dart';
import '../order/outbox.dart';

void showOutboxSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const OutboxSheet(),
  );
}

/// Orders on this phone that the server has not confirmed. Never labelled "sent".
class OutboxSheet extends StatelessWidget {
  const OutboxSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final outbox = context.watch<Outbox>();
    final money = context.watch<MenuRepository>().money;
    final entries = outbox.entries;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
          child: Row(children: [
            Expanded(child: Text(context.t('outbox_waiting', {'n': entries.length}), style: Nami.num(24))),
            TextButton.icon(
              onPressed: () => outbox.flush(force: true),
              icon: const Icon(Icons.refresh),
              label: Text(context.t('retry')),
            ),
          ]),
        ),
        Flexible(
          child: entries.isEmpty
              ? Padding(padding: const EdgeInsets.all(24), child: Text(context.t('done')))
              : ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  children: [for (final e in entries) OutboxCard(entry: e, money: money)],
                ),
        ),
      ]),
    );
  }
}

class OutboxCard extends StatelessWidget {
  const OutboxCard({super.key, required this.entry, required this.money});
  final OutboxEntry entry;
  final Money money;

  @override
  Widget build(BuildContext context) {
    final outbox = context.read<Outbox>();
    final sending = context.watch<Outbox>().isSending(entry.id);
    final color = entry.failed ? Nami.red : Nami.amber;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: NamiCard(
        border: BorderDirectional(start: BorderSide(color: color, width: 5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(entry.label, style: Nami.num(24))),
            Pill(
              label: entry.failed ? context.t('status_failed') : (sending ? context.t('order_sending') : context.t('status_waiting')),
              color: color,
              textColor: entry.failed ? Nami.white : Nami.ink,
              icon: entry.failed ? Icons.error_outline : Icons.schedule,
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            '${context.t('order_items', {'n': entry.itemCount})} · ${money.withCode(entry.total)} · ${hhmm(entry.createdAt)}'
            '${entry.kind == OutboxKind.addItems ? ' · ${entry.payload['order']}' : ''}',
            style: const TextStyle(color: Nami.muted, fontSize: 14),
          ),
          if (entry.lastError != null) ...[
            const SizedBox(height: 6),
            Text(entry.lastError!, style: TextStyle(color: entry.failed ? Nami.red : Nami.muted, fontSize: 14, fontWeight: FontWeight.w500)),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(
              onPressed: sending ? null : () => outbox.retry(entry.id),
              child: Text(context.t('retry')),
            ),
            if (entry.failed) ...[
              OutlinedButton(
                onPressed: () async {
                  await context.read<OrderSender>().returnToDraft(entry.id);
                },
                child: Text(context.t('floor_draft')),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: Nami.red, side: const BorderSide(color: Nami.red, width: 1.5)),
                onPressed: () async {
                  if (await confirmDialog(context, title: '${context.t('discard')}: ${entry.label}?', confirm: context.t('discard'), destructive: true)) {
                    await outbox.remove(entry.id);
                  }
                },
                child: Text(context.t('discard')),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}
