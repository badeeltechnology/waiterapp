import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../features/calls/calls_controller.dart';
import '../features/order/send_controller.dart';
import 'nav.dart';
import 'notices.dart';

/// Sits above the navigator: the Send result, short notices and the guest
/// call banner are visible on every screen, also on pushed ones.
class OverlayHost extends StatelessWidget {
  const OverlayHost({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final send = context.watch<SendController>();
    final notices = context.watch<Notices>();
    final result = send.currentResult;
    final fullResult = result != null && !result.background ? result : null;
    final toastJob = result != null && result.background ? result : null;
    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          ValueListenableBuilder<int>(
            valueListenable: currentHomeTab,
            builder: (context, tab, _) {
              final banner = CallBanner.shows(context.watch<CallsController>(), tab);
              return Column(
                children: [
                  if (banner) const CallBanner(),
                  Expanded(
                    child: MediaQuery.removePadding(context: context, removeTop: banner, child: child),
                  ),
                ],
              );
            },
          ),
          if (toastJob != null)
            _Toast(
              key: ValueKey('job_${toastJob.id}'),
              color: Nami.green,
              icon: Icons.check_circle,
              text: context.t('toast_sent_bg', {'table': toastJob.label}),
              sub: toastJob.order?.name,
              onDone: () => send.acknowledge(toastJob),
            )
          else if (notices.current != null && fullResult == null)
            _noticeToast(context, notices, notices.current!),
          if (fullResult != null)
            Positioned.fill(
              child: SendResultPanel(key: ValueKey('result_${fullResult.id}_${fullResult.phase.name}'), job: fullResult),
            ),
        ],
      ),
    );
  }

  Widget _noticeToast(BuildContext context, Notices notices, Notice n) {
    final (color, icon, key) = switch (n.kind) {
      NoticeKind.accepted => (Nami.teal, Icons.thumb_up_alt, 'toast_accepted'),
      NoticeKind.ready => (Nami.green, Icons.room_service, 'toast_ready'),
      NoticeKind.rejected => (Nami.red, Icons.block, 'toast_rejected'),
      NoticeKind.sent => (Nami.green, Icons.check_circle, 'toast_sent_bg'),
    };
    return _Toast(
      key: ValueKey(n),
      color: color,
      icon: icon,
      text: context.t(key, {'table': n.title}),
      sub: n.order,
      long: n.kind == NoticeKind.ready || n.kind == NoticeKind.rejected,
      onTap: () => goHomeTab(1),
      onDone: () => notices.dismiss(n),
    );
  }
}

class _Toast extends StatefulWidget {
  const _Toast({
    super.key,
    required this.color,
    required this.icon,
    required this.text,
    this.sub,
    required this.onDone,
    this.onTap,
    this.long = false,
  });
  final Color color;
  final IconData icon;
  final String text;
  final String? sub;
  final VoidCallback onDone;
  final VoidCallback? onTap;
  final bool long;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer(Duration(seconds: widget.long ? 8 : 4), widget.onDone);
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Positioned(
      left: 12,
      right: 12,
      top: top + 8,
      child: Semantics(
        liveRegion: true,
        child: Material(
          key: const Key('toast'),
          color: widget.color,
          elevation: 6,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              widget.onDone();
              widget.onTap?.call();
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(widget.icon, color: Nami.white, size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.text,
                            style: const TextStyle(color: Nami.white, fontSize: 17, fontWeight: FontWeight.w700),
                          ),
                          if (widget.sub != null) Text(widget.sub!, style: const TextStyle(color: Nami.white, fontSize: 14)),
                        ],
                      ),
                    ),
                    const Icon(Icons.close, color: Nami.white),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen answer to a tap on Send. Green: done. Amber: saved, not sent
/// yet. Red: refused. Never a silent state.
class SendResultPanel extends StatefulWidget {
  const SendResultPanel({super.key, required this.job});
  final SendJob job;

  @override
  State<SendResultPanel> createState() => _SendResultPanelState();
}

class _SendResultPanelState extends State<SendResultPanel> {
  Timer? _auto;

  @override
  void initState() {
    super.initState();
    // Success dismisses itself; problems wait for the waiter.
    if (widget.job.phase == SendPhase.sent) {
      _auto = Timer(const Duration(milliseconds: 2500), _dismiss);
    }
  }

  @override
  void dispose() {
    _auto?.cancel();
    super.dispose();
  }

  void _dismiss() {
    if (!mounted) return;
    context.read<SendController>().acknowledge(widget.job);
  }

  @override
  Widget build(BuildContext context) {
    final j = widget.job;
    final c = context.read<SendController>();
    final (Color bg, Color fg, IconData icon, String title, String? body) = switch (j.phase) {
      SendPhase.sent => (Nami.green, Nami.white, Icons.check_circle_rounded, context.t(j.isRound ? 'send_ok_round' : 'send_ok_title'), null),
      SendPhase.queued when j.waitingForFirstRound => (
        Nami.amber,
        Nami.ink,
        Icons.schedule_send,
        context.t('send_round_wait_title'),
        context.t('send_round_wait_body'),
      ),
      SendPhase.queued when j.maybeArrived => (
        Nami.amber,
        Nami.ink,
        Icons.hourglass_top_rounded,
        context.t('send_timeout_title'),
        context.t('send_timeout_body'),
      ),
      SendPhase.queued => (Nami.amber, Nami.ink, Icons.cloud_off, context.t('send_queued_title'), context.t('send_queued_body')),
      SendPhase.failed => (Nami.red, Nami.white, Icons.error_rounded, context.t('send_failed_title'), context.t('send_failed_body')),
      SendPhase.sending => (Nami.deep, Nami.white, Icons.send, context.t('send_sending_title'), null),
    };
    final time = hhmm(j.finishedAt ?? j.startedAt);
    final meta = context.t('send_meta', {
      'table': isolate([j.label, ?j.room].join(' · ')),
      'n': isolate('${j.itemCount}'),
      't': isolate(time),
    });
    final bottom = MediaQuery.paddingOf(context).bottom;
    final top = MediaQuery.paddingOf(context).top;

    Widget primary(String label, VoidCallback onTap, {Key? key}) => SizedBox(
      width: double.infinity,
      height: 64,
      child: FilledButton(
        key: key,
        style: FilledButton.styleFrom(
          backgroundColor: fg,
          foregroundColor: bg,
          textStyle: const TextStyle(fontFamily: Nami.bodyFont, fontSize: 19, fontWeight: FontWeight.w700),
        ),
        onPressed: onTap,
        child: Text(label, style: TextStyle(color: bg)),
      ),
    );
    Widget secondary(String label, VoidCallback onTap, {Key? key}) => SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        key: key,
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          side: BorderSide(color: fg, width: 2),
        ),
        onPressed: onTap,
        child: Text(label),
      ),
    );

    final actions = <Widget>[
      if (j.phase == SendPhase.sent) ...[
        primary(context.t('ok'), _dismiss, key: const Key('result_ok')),
        const SizedBox(height: 10),
        secondary(context.t('send_find'), () {
          _dismiss();
          goHomeTab(1);
        }, key: const Key('result_find')),
      ] else if (j.phase == SendPhase.queued) ...[
        primary(context.t('send_keep'), () {
          _dismiss();
        }, key: const Key('result_keep')),
        if (!j.waitingForFirstRound) ...[
          const SizedBox(height: 10),
          secondary(context.t('send_retry'), () => c.retry(j.id), key: const Key('result_retry')),
        ],
      ] else if (j.phase == SendPhase.failed) ...[
        primary(context.t('send_retry'), () => c.retry(j.id), key: const Key('result_retry')),
        const SizedBox(height: 10),
        secondary(context.t('send_edit'), () => c.editDraft(j), key: const Key('result_edit')),
        const SizedBox(height: 10),
        secondary(context.t('send_keep'), _dismiss, key: const Key('result_keep')),
      ],
    ];

    return Semantics(
      liveRegion: true,
      container: true,
      child: GestureDetector(
        key: const Key('send_result'),
        behavior: HitTestBehavior.opaque,
        onTap: j.phase == SendPhase.sent ? _dismiss : null,
        child: ColoredBox(
          color: bg,
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, top + 24, 24, bottom + 20),
            child: Column(
              children: [
                const Spacer(),
                Icon(icon, size: 120, color: fg),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Nami.num(40, color: fg),
                ),
                const SizedBox(height: 14),
                if (j.order != null)
                  Text(
                    j.order!.name,
                    key: const Key('result_order_no'),
                    textAlign: TextAlign.center,
                    style: Nami.num(32, color: fg, weight: FontWeight.w600),
                  ),
                const SizedBox(height: 6),
                Text(
                  meta,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 19, color: fg, fontWeight: FontWeight.w600),
                ),
                if (j.error != null && j.phase == SendPhase.failed) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0x33000000), borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      j.error!.message,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 17, color: fg, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
                if (body != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 17, color: fg, height: 1.35),
                  ),
                ],
                const Spacer(),
                ...actions,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A guest is calling: visible over every screen (also mid-order), with a
/// one-tap "I'm going". The draft stays where it is.
class CallBanner extends StatelessWidget {
  const CallBanner({super.key});

  /// Not on the Calls tab (the list is there) and someone is waiting.
  static bool shows(CallsController calls, int tab) => tab != 2 && calls.calls.any((c) => !c.isAccepted);

  @override
  Widget build(BuildContext context) {
    final calls = context.watch<CallsController>();
    final waiting = calls.calls.where((c) => !c.isAccepted).toList();
    if (waiting.isEmpty) return const SizedBox.shrink();
    final first = waiting.first;
    final top = MediaQuery.paddingOf(context).top;
    final busy = calls.busy.contains(first.name);
    return Material(
      key: const Key('call_banner'),
      color: Nami.red,
      child: InkWell(
        onTap: () => goHomeTab(2),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, top + 6, 10, 6),
          child: Row(
            children: [
              const Icon(Icons.notifications_active, color: Nami.white, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.t('call_banner', {'table': first.table ?? '?'}),
                      style: const TextStyle(color: Nami.white, fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    Text(
                      [
                        ?first.guestNote,
                        ?first.room,
                        if (waiting.length > 1) context.t('call_banner_more', {'n': waiting.length - 1}),
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Nami.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 48,
                child: FilledButton(
                  key: const Key('call_banner_go'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Nami.white,
                    foregroundColor: Nami.red,
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onPressed: busy ? null : () => calls.accept(first.name),
                  child: Text(context.t('calls_accept'), style: const TextStyle(color: Nami.red)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
