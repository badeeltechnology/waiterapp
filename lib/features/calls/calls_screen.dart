import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/alerts.dart';
import '../../core/api/api_exception.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/models/order.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'calls_controller.dart';

class CallsScreen extends StatefulWidget {
  const CallsScreen({super.key});
  @override
  State<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends State<CallsScreen> {
  bool? _notifyOn;

  @override
  void initState() {
    super.initState();
    _checkNotify();
  }

  Future<void> _checkNotify() async {
    final on = await context.read<Alerts>().enabled();
    if (mounted) setState(() => _notifyOn = on);
  }

  Future<void> _accept(CallsController c, GuestCall call) async {
    HapticFeedback.mediumImpact();
    try {
      final takenBy = await c.accept(call.name);
      if (!mounted) return;
      if (takenBy != null) showMessage(context, context.t('calls_taken_by', {'n': takenBy}), error: true);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  Future<void> _attended(CallsController c, GuestCall call) async {
    try {
      await c.attended(call.name);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<CallsController>();
    final now = ServerClock.now();
    final calls = [...c.calls]..sort((a, b) {
        // Waiting calls first, oldest first.
        if (a.isAccepted != b.isAccepted) return a.isAccepted ? 1 : -1;
        return (a.created ?? now).compareTo(b.created ?? now);
      });
    return Scaffold(
      appBar: AppBar(title: Text(context.t('nav_calls'))),
      body: Column(children: [
        if (_notifyOn == false)
          StatusStrip(
            text: context.t('calls_notify_off'),
            color: Nami.red,
            icon: Icons.notifications_off,
            onTap: () async {
              await context.read<Alerts>().requestPermission();
              await _checkNotify();
            },
          ),
        Expanded(
          child: RefreshIndicator(
            color: Nami.teal,
            onRefresh: c.refresh,
            child: calls.isEmpty
                ? ListView(children: [
                    SizedBox(
                      height: 360,
                      child: EmptyState(
                        icon: Icons.notifications_none,
                        text: c.error != null ? c.error!.message : context.t('calls_empty'),
                      ),
                    ),
                  ])
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: calls.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => CallCard(
                      call: calls[i],
                      mine: calls[i].acceptedBy == c.myWaiter,
                      busy: c.busy.contains(calls[i].name),
                      minutes: minutesSince(calls[i].created, now),
                      onAccept: () => _accept(c, calls[i]),
                      onAttended: () => _attended(c, calls[i]),
                    ),
                  ),
          ),
        ),
      ]),
    );
  }
}

class CallCard extends StatelessWidget {
  const CallCard({
    super.key,
    required this.call,
    required this.mine,
    required this.busy,
    required this.minutes,
    required this.onAccept,
    required this.onAttended,
  });
  final GuestCall call;
  final bool mine;
  final bool busy;
  final int minutes;
  final VoidCallback onAccept;
  final VoidCallback onAttended;

  @override
  Widget build(BuildContext context) {
    final waiting = !call.isAccepted;
    final takenByOther = call.isAccepted && !mine;
    final accent = waiting ? Nami.red : (mine ? Nami.teal : Nami.muted);
    return NamiCard(
      border: BorderDirectional(start: BorderSide(color: accent, width: 6)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(call.table ?? '?', style: Nami.num(34)),
              if (call.room != null) Text(call.room!, style: const TextStyle(color: Nami.muted, fontSize: 15)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(context.t('calls_ago', {'n': minutes}), style: Nami.num(20, color: minutes >= 3 && waiting ? Nami.red : Nami.muted)),
            const SizedBox(height: 4),
            Pill(
              label: waiting
                  ? context.t('calls_waiting')
                  : (mine ? context.t('calls_yours') : context.t('calls_taken_by', {'n': call.acceptedBy})),
              color: accent,
            ),
          ]),
        ]),
        if (call.guestNote != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Nami.cream, borderRadius: BorderRadius.circular(4)),
            child: Text(call.guestNote!, style: const TextStyle(fontSize: 16)),
          ),
        ],
        if (!takenByOther) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: waiting
                ? FilledButton.icon(
                    key: Key('call_accept_${call.name}'),
                    onPressed: busy ? null : onAccept,
                    icon: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)) : const Icon(Icons.directions_walk),
                    label: Text(context.t('calls_accept')),
                  )
                : FilledButton.icon(
                    key: Key('call_done_${call.name}'),
                    style: FilledButton.styleFrom(backgroundColor: Nami.teal, foregroundColor: Nami.white),
                    onPressed: busy ? null : onAttended,
                    icon: const Icon(Icons.check),
                    label: Text(context.t('calls_attended')),
                  ),
          ),
        ],
      ]),
    );
  }
}
