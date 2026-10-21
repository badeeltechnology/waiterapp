import 'package:uuid/uuid.dart';

import '../../core/api/waiter_api.dart';
import 'cart.dart';
import 'outbox.dart';

/// Turns a table draft into an outbox entry and tries to send it.
///
/// The draft leaves the cart only when the entry is safely persisted in the
/// outbox; if the server refuses it straight away the lines go back to the draft.
class OrderSender {
  OrderSender({required this.carts, required this.outbox, String Function()? newId})
      : _newId = newId ?? (() => const Uuid().v4());

  final CartStore carts;
  final Outbox outbox;
  final String Function() _newId;

  static OutboxSender senderFor(WaiterApi api) => (entry) =>
      entry.kind == OutboxKind.create ? api.createOrder(entry.payload) : api.addItems(entry.payload);

  /// [existingOrder] set: adds a round to that open order (add_items).
  Future<SendOutcome> send({
    required CartTarget target,
    required String posProfile,
    required String user,
    String? existingOrder,
  }) async {
    final cart = carts.cartFor(target.key);
    if (cart.isEmpty) throw StateError('empty cart');
    final id = _newId();
    final items = cart.toPayloadItems();
    final Map<String, dynamic> payload;
    final OutboxKind kind;
    if (existingOrder != null) {
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
    );
    final guests = cart.guests;
    final notes = cart.notes;
    await outbox.enqueue(entry);
    carts.clear(target.key);

    final outcome = await outbox.send(id);
    if (outcome is RefusedOutcome) {
      // Refused at once: give the waiter the draft back to fix it.
      await outbox.remove(id);
      carts.restore(target.key, [for (final l in entry.lines) CartLine.fromJson(l)], guests: guests, notes: notes);
    }
    return outcome;
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
