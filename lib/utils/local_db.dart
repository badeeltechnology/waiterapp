import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// Local SQLite database for offline order queuing
class LocalDb {
  static Database? _db;

  static Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'servepos_waiter.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE queued_orders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            waiter_name TEXT NOT NULL,
            order_data TEXT NOT NULL,
            status TEXT DEFAULT 'queued',
            created_at TEXT NOT NULL,
            synced_at TEXT,
            error TEXT
          )
        ''');
      },
    );
  }

  /// Queue an order for later sync
  static Future<int> queueOrder(String waiterName, Map<String, dynamic> orderData) async {
    final db = await database;
    return db.insert('queued_orders', {
      'waiter_name': waiterName,
      'order_data': jsonEncode(orderData),
      'status': 'queued',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  /// Get all queued (unsent) orders
  static Future<List<Map<String, dynamic>>> getQueuedOrders() async {
    final db = await database;
    return db.query('queued_orders', where: "status = 'queued'", orderBy: 'created_at ASC');
  }

  /// Mark an order as synced
  static Future<void> markSynced(int id) async {
    final db = await database;
    await db.update(
      'queued_orders',
      {'status': 'synced', 'synced_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Mark an order as failed with error
  static Future<void> markFailed(int id, String error) async {
    final db = await database;
    await db.update(
      'queued_orders',
      {'status': 'queued', 'error': error},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Get count of queued orders
  static Future<int> getQueuedCount() async {
    final db = await database;
    final result = await db.rawQuery("SELECT COUNT(*) as c FROM queued_orders WHERE status = 'queued'");
    return result.first['c'] as int? ?? 0;
  }

  /// Delete synced orders older than 1 day
  static Future<void> cleanupSynced() async {
    final db = await database;
    final cutoff = DateTime.now().subtract(const Duration(days: 1)).toIso8601String();
    await db.delete('queued_orders', where: "status = 'synced' AND synced_at < ?", whereArgs: [cutoff]);
  }
}
