import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/order.dart';
import '../../core/storage.dart';

enum OutboxKind { create, addItems }

/// An order (or extra round) the server has not confirmed yet.
///
/// [id] is the `client_request_id` and never changes, so every retry is
/// idempotent on the server.
class OutboxEntry {
  OutboxEntry({
    required this.id,
    required this.kind,
    required this.payload,
    required this.user,
    required this.label,
    required this.cartKey,
    required this.total,
    required this.itemCount,
    required this.lines,
    required this.createdAt,
    this.attempts = 0,
    this.nextAttemptAt,
    this.lastError,
    this.failed = false,
  });

  final String id;
  final OutboxKind kind;
  final Map<String, dynamic> payload;

  /// The signed-in user who created it; never sent under someone else's login.
  final String user;
  final String label;
  final String cartKey;
  final double total;
  final int itemCount;

  /// Cart lines as JSON, so a refused order can go back to the draft.
  final List<Map<String, dynamic>> lines;
  final DateTime createdAt;
  int attempts;
  DateTime? nextAttemptAt;
  String? lastError;

  /// The server refused it (validation). Needs the waiter: retry, discard or edit.
  bool failed;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'payload': payload,
        'user': user,
        'label': label,
        'cart_key': cartKey,
        'total': total,
        'item_count': itemCount,
        'lines': lines,
        'created_at': createdAt.toIso8601String(),
        'attempts': attempts,
        'next_attempt_at': nextAttemptAt?.toIso8601String(),
        'last_error': lastError,
        'failed': failed,
      };

  factory OutboxEntry.fromJson(Map<String, dynamic> j) => OutboxEntry(
        id: '${j['id']}',
        kind: OutboxKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => OutboxKind.create),
        payload: Map<String, dynamic>.from(j['payload'] as Map),
        user: '${j['user'] ?? ''}',
        label: '${j['label'] ?? ''}',
        cartKey: '${j['cart_key'] ?? ''}',
        total: (j['total'] as num?)?.toDouble() ?? 0,
        itemCount: (j['item_count'] as num?)?.toInt() ?? 0,
        lines: [for (final l in (j['lines'] as List? ?? const [])) Map<String, dynamic>.from(l as Map)],
        createdAt: DateTime.tryParse('${j['created_at']}') ?? DateTime.now(),
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
        nextAttemptAt: j['next_attempt_at'] == null ? null : DateTime.tryParse('${j['next_attempt_at']}'),
        lastError: j['last_error'] as String?,
        failed: j['failed'] == true,
      );
}

sealed class SendOutcome {
  const SendOutcome();
}

class SentOutcome extends SendOutcome {
  const SentOutcome(this.order);
  final Order order;
}

/// Not confirmed; still queued and will retry by itself.
class QueuedOutcome extends SendOutcome {
  const QueuedOutcome(this.error);
  final ApiException error;
}

/// The server refused it. It stays in the outbox marked failed.
class RefusedOutcome extends SendOutcome {
  const RefusedOutcome(this.error);
  final ApiException error;
}

typedef OutboxSender = Future<Order> Function(OutboxEntry entry);

/// Persistent queue of unconfirmed orders with exponential backoff.
class Outbox extends ChangeNotifier {
  Outbox({
    required this.sender,
    JsonStore? store,
    DateTime Function()? clock,
    this.baseDelay = const Duration(seconds: 5),
    this.maxDelay = const Duration(minutes: 2),
  })  : _store = store,
        _clock = clock ?? DateTime.now;

  final OutboxSender sender;
  final JsonStore? _store;
  final DateTime Function() _clock;
  final Duration baseDelay;
  final Duration maxDelay;

  final List<OutboxEntry> _entries = [];
  final Set<String> _inFlight = {};
  Timer? _timer;
  bool _flushing = false;

  /// Only entries of this user are sent; set by the session.
  String? currentUser;

  /// Called after the server confirms an entry.
  void Function(OutboxEntry entry, Order order)? onSent;

  List<OutboxEntry> get entries => List.unmodifiable(_entries.where((e) => e.user == currentUser));
  int get waitingCount => entries.where((e) => !e.failed).length;
  int get failedCount => entries.where((e) => e.failed).length;
  int get count => entries.length;
  List<OutboxEntry> forCart(String key) => entries.where((e) => e.cartKey == key).toList();
  bool isSending(String id) => _inFlight.contains(id);

  Duration backoffFor(int attempts) {
    if (attempts <= 0) return Duration.zero;
    final ms = baseDelay.inMilliseconds * math.pow(2, attempts - 1);
    return Duration(milliseconds: math.min(ms.toInt(), maxDelay.inMilliseconds));
  }

  Future<void> load() async {
    final raw = await _store?.load('outbox');
    _entries.clear();
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          try {
            _entries.add(OutboxEntry.fromJson(Map<String, dynamic>.from(e)));
          } catch (_) {}
        }
      }
    }
    notifyListeners();
  }

  Future<void> _persist() => _store?.save('outbox', [for (final e in _entries) e.toJson()]) ?? Future.value();

  /// Adds an entry. Enqueuing an id that is already queued is a no-op and
  /// returns the existing entry (double taps never create two orders).
  Future<OutboxEntry> enqueue(OutboxEntry entry) async {
    final existing = _entries.where((e) => e.id == entry.id).firstOrNull;
    if (existing != null) return existing;
    assert(entry.payload['client_request_id'] == entry.id, 'payload must carry the same client_request_id');
    _entries.add(entry);
    await _persist();
    notifyListeners();
    return entry;
  }

  /// Sends one entry now.
  Future<SendOutcome> send(String id) async {
    final entry = _entries.where((e) => e.id == id).firstOrNull;
    if (entry == null) throw StateError('No outbox entry $id');
    if (_inFlight.contains(id)) {
      return QueuedOutcome(const NetworkException('Already sending.'));
    }
    _inFlight.add(id);
    notifyListeners();
    try {
      final order = await sender(entry);
      _entries.removeWhere((e) => e.id == id);
      await _persist();
      onSent?.call(entry, order);
      return SentOutcome(order);
    } on ApiException catch (e) {
      entry.attempts++;
      entry.lastError = e.message;
      if (e is SessionExpiredException) {
        // Keep it; it goes out after the same waiter signs in again.
        entry.nextAttemptAt = _clock();
        await _persist();
        return QueuedOutcome(e);
      }
      if (e.isTransient) {
        entry.nextAttemptAt = _clock().add(backoffFor(entry.attempts));
        await _persist();
        return QueuedOutcome(e);
      }
      entry.failed = true;
      await _persist();
      return RefusedOutcome(e);
    } catch (e) {
      entry.attempts++;
      entry.lastError = 'Unexpected error';
      entry.nextAttemptAt = _clock().add(backoffFor(entry.attempts));
      await _persist();
      return QueuedOutcome(const BadResponseException());
    } finally {
      _inFlight.remove(id);
      notifyListeners();
    }
  }

  /// Sends every due entry of the current user, oldest first. Stops at the
  /// first network-type failure (no point hammering a dead link).
  Future<void> flush({bool force = false}) async {
    if (_flushing || currentUser == null) return;
    _flushing = true;
    try {
      final now = _clock();
      final due = entries
          .where((e) => !e.failed && (force || e.nextAttemptAt == null || !e.nextAttemptAt!.isAfter(now)))
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      for (final e in due) {
        final r = await send(e.id);
        if (r is QueuedOutcome && (r.error is NetworkException || r.error is TimeoutApiException || r.error is SessionExpiredException)) {
          break;
        }
      }
    } finally {
      _flushing = false;
    }
  }

  Future<SendOutcome> retry(String id) async {
    final entry = _entries.where((e) => e.id == id).firstOrNull;
    if (entry == null) throw StateError('No outbox entry $id');
    entry.failed = false;
    entry.nextAttemptAt = null;
    return send(id);
  }

  Future<OutboxEntry?> remove(String id) async {
    final entry = _entries.where((e) => e.id == id).firstOrNull;
    _entries.removeWhere((e) => e.id == id);
    await _persist();
    notifyListeners();
    return entry;
  }

  /// Drops entries that belong to other users (a different waiter signed in).
  Future<void> dropOthers(String user) async {
    _entries.removeWhere((e) => e.user != user);
    await _persist();
    notifyListeners();
  }

  void start({Duration tick = const Duration(seconds: 5)}) {
    _timer?.cancel();
    _timer = Timer.periodic(tick, (_) => flush());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> wipe() async {
    stop();
    _entries.clear();
    await _store?.save('outbox', null);
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
