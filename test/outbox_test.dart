import 'package:flutter_test/flutter_test.dart';
import 'package:servepos_waiter/core/api/api_exception.dart';
import 'package:servepos_waiter/core/models/order.dart';
import 'package:servepos_waiter/core/storage.dart';
import 'package:servepos_waiter/features/order/cart.dart';
import 'package:servepos_waiter/features/order/order_sender.dart';
import 'package:servepos_waiter/features/order/outbox.dart';

import 'support/fakes.dart';

void main() {
  late DateTime now;
  late List<String> sentIds;
  late List<Object> script; // what the "server" does next: ApiException or 'ok'

  Future<Order> sender(OutboxEntry e) async {
    sentIds.add(e.payload['client_request_id'] as String);
    final next = script.isEmpty ? 'ok' : script.removeAt(0);
    if (next is ApiException) throw next;
    return Order.fromJson(orderJson(name: 'WO-${e.id}'));
  }

  Outbox make({JsonStore? store}) => Outbox(sender: sender, store: store, clock: () => now)..currentUser = 'ahmed@example.com';

  OutboxEntry entry(String id, {String user = 'ahmed@example.com'}) => OutboxEntry(
        id: id,
        kind: OutboxKind.create,
        payload: {'client_request_id': id, 'items': []},
        user: user,
        label: 'T4',
        cartKey: 'table:T4',
        total: 10,
        itemCount: 1,
        lines: const [],
        createdAt: now,
      );

  setUp(() {
    now = DateTime(2026, 10, 21, 12);
    sentIds = [];
    script = [];
  });

  test('enqueue is idempotent by client_request_id', () async {
    final o = make();
    await o.enqueue(entry('A'));
    await o.enqueue(entry('A'));
    expect(o.count, 1);
  });

  test('retries reuse the same client_request_id until confirmed', () async {
    final o = make();
    await o.enqueue(entry('A'));
    script = [const NetworkException(), const TimeoutApiException(), const ServerException('Bad gateway', statusCode: 502)];
    expect(await o.send('A'), isA<QueuedOutcome>());
    now = now.add(const Duration(minutes: 5));
    await o.flush();
    now = now.add(const Duration(minutes: 5));
    await o.flush();
    expect(o.waitingCount, 1, reason: 'never reported sent while the server has not confirmed');
    now = now.add(const Duration(minutes: 5));
    await o.flush();
    expect(o.count, 0);
    expect(sentIds, ['A', 'A', 'A', 'A']);
  });

  test('backoff grows and is capped; not due entries are skipped', () async {
    final o = make();
    expect(o.backoffFor(1), const Duration(seconds: 5));
    expect(o.backoffFor(2), const Duration(seconds: 10));
    expect(o.backoffFor(3), const Duration(seconds: 20));
    expect(o.backoffFor(10), const Duration(minutes: 2));
    await o.enqueue(entry('A'));
    script = [const NetworkException()];
    await o.send('A');
    await o.flush(); // not due yet (5s)
    expect(sentIds, ['A']);
    now = now.add(const Duration(seconds: 6));
    await o.flush();
    expect(sentIds, ['A', 'A']);
  });

  test('validation refusal marks failed and stops auto retry; retry() clears it', () async {
    final o = make();
    await o.enqueue(entry('A'));
    script = [const ServerException('Item is not available', statusCode: 417)];
    final r = await o.send('A');
    expect(r, isA<RefusedOutcome>());
    expect(o.failedCount, 1);
    now = now.add(const Duration(hours: 1));
    await o.flush();
    expect(sentIds, ['A'], reason: 'failed entries wait for the waiter');
    expect(await o.retry('A'), isA<SentOutcome>());
    expect(o.count, 0);
  });

  test('flush stops at the first network failure', () async {
    final o = make();
    await o.enqueue(entry('A'));
    now = now.add(const Duration(seconds: 1));
    await o.enqueue(entry('B'));
    script = [const NetworkException()];
    await o.flush(force: true);
    expect(sentIds, ['A']);
  });

  test('entries of another user are not sent and are dropped on their login', () async {
    final o = make();
    await o.enqueue(entry('A', user: 'sara@example.com'));
    await o.flush(force: true);
    expect(sentIds, isEmpty);
    expect(o.count, 0, reason: 'only the current user\'s entries are visible');
    await o.dropOthers('ahmed@example.com');
    o.currentUser = 'sara@example.com';
    expect(o.count, 0);
  });

  test('queue survives restart', () async {
    final store = MemoryJsonStore();
    final a = make(store: store);
    await a.enqueue(entry('A'));
    final b = make(store: store);
    await b.load();
    expect(b.entries.single.id, 'A');
    expect(b.entries.single.payload['client_request_id'], 'A');
  });

  group('OrderSender', () {
    final fries = sampleMenu().items.firstWhere((i) => i.itemCode == 'FRIES');

    test('offline: draft moves to the outbox, nothing claims sent', () async {
      final carts = CartStore();
      final o = make();
      final s = OrderSender(carts: carts, outbox: o, newId: () => 'REQ-1');
      const t = CartTarget.table(table: 'T4', room: 'Terrace');
      carts.add(t.key, CartLine.fromItem(fries, qty: 2));
      script = [const NetworkException()];
      final r = await s.send(target: t, posProfile: 'Cocktail Bar', user: 'ahmed@example.com');
      expect(r, isA<QueuedOutcome>());
      expect(carts.cartFor(t.key).isEmpty, isTrue);
      expect(o.forCart(t.key).single.payload, containsPair('client_request_id', 'REQ-1'));
      expect(o.forCart(t.key).single.payload['items'], [
        {'item_code': 'FRIES', 'qty': 2, 'modifiers': [], 'special_instructions': ''},
      ]);
    });

    test('refused at once: kept as Not sent (Retry with the same id), Edit puts the lines back in the draft', () async {
      final carts = CartStore();
      final o = make();
      final s = OrderSender(carts: carts, outbox: o, newId: () => 'REQ-2');
      const t = CartTarget.table(table: 'T4');
      carts.add(t.key, CartLine.fromItem(fries));
      carts.setGuests(t.key, 3);
      script = [const ServerException('Table is closed', statusCode: 417)];
      final r = await s.send(target: t, posProfile: 'P', user: 'ahmed@example.com');
      expect(r, isA<RefusedOutcome>());
      expect(o.count, 1);
      expect(o.entries.single.failed, isTrue);
      expect(carts.cartFor(t.key).itemCount, 0, reason: 'the draft is not silently refilled (that invited a second Send with a new id)');
      await s.returnToDraft('REQ-2');
      expect(o.count, 0);
      expect(carts.cartFor(t.key).itemCount, 1);
      expect(carts.cartFor(t.key).guests, 3);
    });

    test('occupied table uses add_items with the open order', () async {
      final carts = CartStore();
      final o = make();
      final s = OrderSender(carts: carts, outbox: o, newId: () => 'REQ-3');
      const t = CartTarget.table(table: 'T2');
      carts.add(t.key, CartLine.fromItem(fries));
      OutboxEntry? seen;
      o.onSent = (e, _) => seen = e;
      final r = await s.send(target: t, posProfile: 'P', user: 'ahmed@example.com', existingOrder: 'WO-2026-00119');
      expect(r, isA<SentOutcome>());
      expect(seen!.kind, OutboxKind.addItems);
      expect(seen!.payload, {
        'order': 'WO-2026-00119',
        'client_request_id': 'REQ-3',
        'items': [
          {'item_code': 'FRIES', 'qty': 1, 'modifiers': [], 'special_instructions': ''},
        ],
      });
    });
  });
}
