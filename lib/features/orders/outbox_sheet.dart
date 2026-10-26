import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../order/menu_repository.dart';
import '../order/outbox.dart';
import '../order/send_controller.dart';

void showOutboxSheet(BuildContext context) {
  showModalBottomSheet<void>(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => const OutboxSheet());
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
            child: Row(
              children: [
                Expanded(child: Text(context.t('outbox_waiting', {'n': entries.length}), style: Nami.num(24))),
                TextButton.icon(
                  onPressed: outbox.isAnySending ? null : () => outbox.flush(force: true),
                  icon: const Icon(Icons.refresh),
                  label: Text(context.t('retry')),
                ),
              ],
            ),
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
        ],
      ),
    );
  }
}

class OutboxCard extends StatelessWidget {
  const OutboxCard({super.key, required this.entry, required this.money});
  final OutboxEntry entry;
  final Money money;

  @override
  Widget build(BuildContext context) {
    final outbox = context.watch<Outbox>();
    final send = context.watch<SendController>();
    final sending = outbox.isSending(entry.id) || send.sendingFor(entry.cartKey)?.id == entry.id;
    final waitsForRound = entry.dependsOn != null && entry.payload['order'] == null;
    final (Color color, Color text, IconData icon, String label) = entry.failed
        ? (Nami.red, Nami.white, Icons.error_outline, context.t('status_failed'))
        : sending
        ? (Nami.deep, Nami.white, Icons.send, context.t('status_sending'))
        : (Nami.amber, Nami.ink, Icons.schedule, context.t('status_waiting'));
    final next = entry.nextAttemptAt;
    final detail = [
      context.t('order_items', {'n': entry.itemCount}),
      money.withCode(entry.total),
      context.t('outbox_saved', {'t': hhmm(entry.createdAt)}),
      if (entry.attempts > 1) context.t('outbox_tries', {'n': entry.attempts}),
      if (!entry.failed && !sending && next != null && next.isAfter(DateTime.now()))
        context.t('outbox_next', {'t': DateFormat('HH:mm:ss').format(next)}),
    ].join(' · ');
    final why = waitsForRound ? context.t('outbox_wait_round') : (entry.maybeArrived && !entry.failed ? context.t('outbox_maybe') : entry.lastError);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: NamiCard(
        key: Key('outbox_${entry.id}'),
        border: BorderDirectional(start: BorderSide(color: color, width: 6)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      entry.label,
                      ?entry.room,
                      if (entry.kind == OutboxKind.addItems && entry.payload['order'] != null) '${entry.payload['order']}',
                    ].join(' · '),
                    style: Nami.num(24),
                  ),
                ),
                if (sending)
                  const Padding(
                    padding: EdgeInsetsDirectional.only(end: 8),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5)),
                  ),
                Pill(label: label, color: color, textColor: text, icon: icon, large: true),
              ],
            ),
            const SizedBox(height: 4),
            Text(detail, style: const TextStyle(color: Nami.muted, fontSize: 14)),
            if (why != null) ...[
              const SizedBox(height: 6),
              Text(
                why,
                style: TextStyle(color: entry.failed ? Nami.red : Nami.ink, fontSize: 15, fontWeight: FontWeight.w500),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!waitsForRound)
                  OutlinedButton(
                    key: Key('outbox_retry_${entry.id}'),
                    onPressed: sending ? null : () => send.retry(entry.id),
                    child: Text(context.t('send_retry')),
                  ),
                if (entry.failed) ...[
                  OutlinedButton(
                    onPressed: () async {
                      final job = send.recent.where((j) => j.id == entry.id).firstOrNull;
                      if (job != null) {
                        await send.editDraft(job);
                      } else {
                        await send.sender.returnToDraft(entry.id);
                      }
                    },
                    child: Text(context.t('send_edit')),
                  ),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Nami.red,
                      side: const BorderSide(color: Nami.red, width: 1.5),
                    ),
                    onPressed: () async {
                      if (await confirmDialog(
                        context,
                        title: '${context.t('discard')}: ${entry.label}?',
                        confirm: context.t('discard'),
                        destructive: true,
                      )) {
                        await outbox.remove(entry.id);
                      }
                    },
                    child: Text(context.t('discard')),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
