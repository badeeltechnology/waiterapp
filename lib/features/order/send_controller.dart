import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/order.dart';
import 'cart.dart';
import 'order_sender.dart';
import 'outbox.dart';

enum SendPhase { sending, sent, queued, failed }

/// One tap on Send for one table, from the tap to the server's answer.
/// [id] is the client_request_id and stays the same for every retry.
class SendJob {
  SendJob({
    required this.id,
    required this.cartKey,
    required this.label,
    required this.room,
    required this.itemCount,
    required this.total,
    required this.signature,
    required this.startedAt,
    this.isRound = false,
    this.background = false,
  });

  final String id;
  final String cartKey;
  final String label;
  final String? room;
  final int itemCount;
  final double total;
  final String signature;
  final DateTime startedAt;
  final bool isRound;

  /// Finished by the outbox on its own (not right after a tap): shown as a toast.
  final bool background;

  SendPhase phase = SendPhase.sending;
  Order? order;
  ApiException? error;
  DateTime? finishedAt;

  /// The phone gave up waiting: the order may already be at the till.
  bool get maybeArrived => error is TimeoutApiException;
  bool get offline => error is NetworkException && error is! WaitingForFirstRound;
  bool get waitingForFirstRound => error is WaitingForFirstRound;
}

/// What the "Send again?" question tells the waiter.
class DuplicateHit {
  const DuplicateHit({required this.label, required this.at, this.orderName, this.stillUnsent = false});
  final String label;
  final DateTime at;
  final String? orderName;

  /// The earlier copy is still on this phone (sending or waiting).
  final bool stillUnsent;
}

/// Haptics and a short tone, so the result is felt and heard, not only seen.
abstract class SendFeedback {
  void sending();
  void sent();
  void queued();
  void failed();
}

class DeviceFeedback implements SendFeedback {
  static const _ch = MethodChannel('servepos/feedback');

  Future<void> _tone(String kind) async {
    try {
      await _ch.invokeMethod('tone', {'kind': kind});
    } on MissingPluginException {
      await SystemSound.play(SystemSoundType.click);
    } on PlatformException {
      // ignore
    }
  }

  @override
  void sending() => HapticFeedback.lightImpact();
  @override
  void sent() {
    HapticFeedback.heavyImpact();
    _tone('ok');
  }

  @override
  void queued() {
    HapticFeedback.mediumImpact();
    _tone('wait');
  }

  @override
  void failed() {
    HapticFeedback.vibrate();
    _tone('error');
  }
}

class RecordingFeedback implements SendFeedback {
  final events = <String>[];
  @override
  void sending() => events.add('sending');
  @override
  void sent() => events.add('sent');
  @override
  void queued() => events.add('queued');
  @override
  void failed() => events.add('failed');
}

/// Single-flight Send per table. Lives above the screens, so leaving the
/// screen, double taps or the app going to the background never start a
/// second send of the same draft.
class SendController extends ChangeNotifier {
  SendController({
    required this.sender,
    required this.outbox,
    SendFeedback? feedback,
    DateTime Function()? clock,
    String Function()? newId,
    this.duplicateWindow = const Duration(minutes: 2),
  }) : feedback = feedback ?? DeviceFeedback(),
       _clock = clock ?? DateTime.now,
       _newId = newId ?? (() => const Uuid().v4());

  final OrderSender sender;
  final Outbox outbox;
  final SendFeedback feedback;
  final DateTime Function() _clock;
  final String Function() _newId;
  final Duration duplicateWindow;

  final Map<String, SendJob> _sending = {}; // by cart key
  final Map<String, Future<SendJob>> _running = {}; // by cart key
  final List<SendJob> recent = []; // finished, newest first
  final List<SendJob> _results = []; // waiting to be shown

  /// Result the overlay shows now (oldest first).
  SendJob? get currentResult => _results.firstOrNull;

  SendJob? sendingFor(String cartKey) => _sending[cartKey];
  bool get isSending => _sending.isNotEmpty;

  /// Sent from this phone in the last [duplicateWindow].
  SendJob? recentSentFor(String cartKey) {
    final now = _clock();
    return recent.where((j) => j.cartKey == cartKey && j.phase == SendPhase.sent && now.difference(j.finishedAt!) <= duplicateWindow).firstOrNull;
  }

  static String signatureOfLines(Iterable<CartLine> lines) {
    final parts = [
      for (final l in lines)
        '${l.itemCode}|${(l.modifiers.map((m) => '${m.group}:${m.name}').toList()..sort()).join(',')}|${l.note.trim().toLowerCase()}|${l.qty}',
    ]..sort();
    return parts.join(';');
  }

  static String signatureOf(TableCart cart) => signatureOfLines(cart.lines);

  /// The same items already went (or are going) to this table recently.
  DuplicateHit? duplicateOf(String cartKey, String signature) {
    for (final e in outbox.forCart(cartKey)) {
      if (signatureOfLines(e.lines.map(CartLine.fromJson)) == signature) {
        return DuplicateHit(label: e.label, at: e.createdAt, stillUnsent: true);
      }
    }
    for (final j in _sending.values) {
      if (j.cartKey == cartKey && j.signature == signature) {
        return DuplicateHit(label: j.label, at: j.startedAt, stillUnsent: true);
      }
    }
    final now = _clock();
    for (final j in recent) {
      if (j.cartKey == cartKey && j.phase == SendPhase.sent && j.signature == signature && now.difference(j.finishedAt!) <= duplicateWindow) {
        return DuplicateHit(label: j.label, at: j.finishedAt!, orderName: j.order?.name);
      }
    }
    return null;
  }

  /// Sends the table's draft. Calling it again while it runs returns the same
  /// job: one draft, one client_request_id, one order.
  Future<SendJob> submit({required CartTarget target, required String posProfile, required String user, String? existingOrder}) {
    final running = _running[target.key];
    if (running != null) return running;
    final cart = sender.carts.cartFor(target.key);
    if (cart.isEmpty) throw StateError('empty cart');
    final job = SendJob(
      id: _newId(),
      cartKey: target.key,
      label: target.takeaway ? 'Takeaway' : (target.tableLabel ?? target.table ?? ''),
      room: target.room,
      itemCount: cart.itemCount,
      total: cart.total,
      signature: signatureOf(cart),
      startedAt: _clock(),
      isRound: existingOrder != null || (!target.takeaway && outbox.pendingCreateFor(target.key) != null),
    );
    _sending[target.key] = job;
    feedback.sending();
    final f = _run(job, () => sender.send(target: target, posProfile: posProfile, user: user, existingOrder: existingOrder, id: job.id));
    _running[target.key] = f;
    notifyListeners();
    return f;
  }

  /// Retry of an unconfirmed order: same id, so the server can never make two.
  Future<SendJob> retry(String id) {
    final entry = outbox.byId(id);
    if (entry == null) throw StateError('No outbox entry $id');
    final running = _running[entry.cartKey];
    if (running != null && _sending[entry.cartKey]?.id == id) return running;
    final old = recent.where((j) => j.id == id).firstOrNull;
    _results.removeWhere((j) => j.id == id);
    final job = SendJob(
      id: id,
      cartKey: entry.cartKey,
      label: entry.label,
      room: entry.room,
      itemCount: entry.itemCount,
      total: entry.total,
      signature: old?.signature ?? signatureOfLines(entry.lines.map(CartLine.fromJson)),
      startedAt: entry.createdAt,
      isRound: entry.kind == OutboxKind.addItems,
    );
    recent.removeWhere((j) => j.id == id);
    _sending[entry.cartKey] = job;
    feedback.sending();
    final f = _run(job, () => outbox.retry(id));
    _running[entry.cartKey] = f;
    notifyListeners();
    return f;
  }

  Future<SendJob> _run(SendJob job, Future<SendOutcome> Function() go) async {
    SendOutcome outcome;
    try {
      outcome = await go();
    } on ApiException catch (e) {
      outcome = QueuedOutcome(e);
    } catch (_) {
      outcome = const QueuedOutcome(BadResponseException());
    }
    _sending.remove(job.cartKey);
    _running.remove(job.cartKey);
    _finish(job, outcome);
    return job;
  }

  void _finish(SendJob job, SendOutcome outcome) {
    job.finishedAt = _clock();
    switch (outcome) {
      case SentOutcome(:final order):
        job.phase = SendPhase.sent;
        job.order = order;
        job.error = null;
        feedback.sent();
      case QueuedOutcome(:final error):
        job.phase = SendPhase.queued;
        job.error = error;
        feedback.queued();
      case RefusedOutcome(:final error):
        job.phase = SendPhase.failed;
        job.error = error;
        feedback.failed();
    }
    recent.removeWhere((j) => j.id == job.id);
    recent.insert(0, job);
    if (recent.length > 60) recent.removeLast();
    _results.removeWhere((j) => j.id == job.id);
    _results.add(job);
    notifyListeners();
  }

  /// The outbox confirmed an entry on its own (back online, timer, resume).
  void onOutboxSent(OutboxEntry entry, Order order) {
    if (_sending[entry.cartKey]?.id == entry.id) return; // the tap's own job reports it
    final old = recent.where((j) => j.id == entry.id).firstOrNull;
    final job = SendJob(
      id: entry.id,
      cartKey: entry.cartKey,
      label: entry.label,
      room: entry.room,
      itemCount: entry.itemCount,
      total: entry.total,
      signature: old?.signature ?? signatureOfLines(entry.lines.map(CartLine.fromJson)),
      startedAt: entry.createdAt,
      isRound: entry.kind == OutboxKind.addItems,
      background: true,
    );
    _finish(job, SentOutcome(order));
  }

  /// The overlay was seen / dismissed.
  void acknowledge(SendJob job) {
    if (_results.remove(job)) notifyListeners();
  }

  /// Refused order back into the table's draft so the waiter can fix it.
  /// (Its next Send gets a new id: the server never created the refused one.)
  Future<void> editDraft(SendJob job) async {
    _results.remove(job);
    recent.removeWhere((j) => j.id == job.id);
    await sender.returnToDraft(job.id);
    notifyListeners();
  }

  void clear() {
    _results.clear();
    recent.clear();
    notifyListeners();
  }
}
