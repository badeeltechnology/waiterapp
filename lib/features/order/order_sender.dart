import 'package:uuid/uuid.dart';

import '../../core/api/waiter_api.dart';
import 'cart.dart';
import 'outbox.dart';

/// Turns a table draft into an outbox entry and tries to send it.
///
/// The draft leaves the cart only when the entry is safely persisted in the
/// outbox; if the server refuses it straight away the lines go back to the draft.
class OrderSender {
  OrderSender({required this.carts, required this.outbox, String Function()? newId}) : _newId = newId ?? (() => const Uuid().v4());

  final CartStore carts;
  final Outbox outbox;
  final String Function() _newId;

  static OutboxSender senderFor(WaiterApi api) =>
      (entry) => entry.kind == OutboxKind.create ? api.createOrder(entry.payload) : api.addItems(entry.payload);

  /// [existingOrder] set: adds a round to that open order (add_items).
  Future<SendOutcome> send({required CartTarget target, required String posProfile, required String user, String? existingOrder, String? id}) async {
    final cart = carts.cartFor(target.key);
    if (cart.isEmpty) throw StateError('empty cart');
    id ??= _newId();
    final items = cart.toPayloadItems();
    final Map<String, dynamic> payload;
    final OutboxKind kind;
    // The table's first order is not confirmed yet: this round is added to it
    // once it is, instead of becoming a second order for the same table.
    final parent = existingOrder == null && !target.takeaway ? outbox.pendingCreateFor(target.key) : null;
    if (existingOrder != null || parent != null) {
      kind = OutboxKind.addItems;
      payload = {'order': existingOrder, 'client_request_id': id, 'items': items};
    } else {
      kind = OutboxKind.create;
      payload = {
        'pos_profile': posProfile,
        'client_request_id': id,
        'order_type': target.orderType,
        'table': target.table,
        'room': target.room,
        'guests': cart.guests,
        'notes': cart.notes.trim(),
        'items': items,
      };
    }
    final entry = OutboxEntry(
      id: id,
      kind: kind,
      payload: payload,
      user: user,
      label: target.takeaway ? 'Takeaway' : (target.tableLabel ?? target.table ?? ''),
      cartKey: target.key,
      total: cart.total,
      itemCount: cart.itemCount,
      lines: [for (final l in cart.lines) l.toJson()],
      createdAt: DateTime.now(),
      dependsOn: parent?.id,
      room: target.room,
    );
    await enqueue(entry, target.key);
    return outbox.send(id);
  }

  /// Persists the entry first, then empties the draft: a crash in between
  /// leaves both, and [reconcile] drops the draft lines on the next start.
  Future<void> enqueue(OutboxEntry entry, String cartKey) async {
    await outbox.enqueue(entry);
    carts.clear(cartKey);
  }

  /// Draft lines that are already in the outbox (app killed between saving the
  /// order and clearing the draft) are removed so they cannot be sent twice.
  void reconcile() {
    final queued = {
      for (final e in outbox.entries)
        for (final l in e.lines) '${l['id']}',
    };
    for (final key in carts.draftKeys.toList()) {
      final cart = carts.peek(key)!;
      for (final l in cart.lines.where((l) => queued.contains(l.id)).toList()) {
        carts.setQty(key, l.id, 0);
      }
    }
  }

  /// "Back to draft" for a failed outbox entry.
  Future<void> returnToDraft(String entryId) async {
    final e = await outbox.remove(entryId);
    if (e == null) return;
    carts.restore(
      e.cartKey,
      [for (final l in e.lines) CartLine.fromJson(l)],
      guests: (e.payload['guests'] as num?)?.toInt(),
      notes: e.payload['notes'] as String?,
    );
  }
}
