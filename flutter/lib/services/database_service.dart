import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite persistence service matching the Android Room database schema.
/// Stores transaction history and address-book entries per wallet.
class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = join(dir, 'octra_wallet.db');
    return openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE tx_history (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        wallet_id  TEXT NOT NULL,
        hash       TEXT NOT NULL,
        timestamp  INTEGER NOT NULL,
        from_addr  TEXT NOT NULL,
        to_addr    TEXT NOT NULL,
        amount     TEXT NOT NULL,
        fee        TEXT,
        op_type    TEXT,
        status     TEXT,
        block_hash TEXT,
        json_raw   TEXT,
        UNIQUE(wallet_id, hash)
      )
    ''');
    await db.execute('''
      CREATE TABLE balance_cache (
        wallet_id         TEXT PRIMARY KEY,
        balance_raw       TEXT NOT NULL,
        nonce             INTEGER NOT NULL,
        encrypted_balance TEXT,
        updated_at        INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE address_book (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        wallet_id  TEXT NOT NULL,
        address    TEXT NOT NULL,
        label      TEXT,
        note       TEXT,
        created_at INTEGER NOT NULL,
        UNIQUE(wallet_id, address)
      )
    ''');
    await db.execute('''
      CREATE TABLE token_cache (
        wallet_id    TEXT PRIMARY KEY,
        tokens_json  TEXT NOT NULL,
        updated_at   INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE tx_history ADD COLUMN block_hash TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS token_cache (
          wallet_id    TEXT PRIMARY KEY,
          tokens_json  TEXT NOT NULL,
          updated_at   INTEGER NOT NULL
        )
      ''');
    }
  }

  // ── Transaction history ────────────────────────────────────────────────────

  /// Insert or replace a list of raw transaction maps for a wallet.
  Future<void> upsertTxHistory(
      String walletId, List<Map<String, dynamic>> txList) async {
    final db = await database;
    final batch = db.batch();
    for (final tx in txList) {
      final hash = tx['hash']?.toString() ?? tx['tx_hash']?.toString() ?? '';
      if (hash.isEmpty) continue;
      batch.insert(
        'tx_history',
        {
          'wallet_id': walletId,
          'hash': hash,
          'timestamp': _parseTs(tx['timestamp']),
          'from_addr': tx['from']?.toString() ??
              tx['from_']?.toString() ??
              tx['sender']?.toString() ??
              '',
          'to_addr':
              (tx['to_'] ?? tx['to'] ?? tx['recipient'] ?? tx['receiver'])
                      ?.toString() ??
                  '',
          'amount': (tx['amount_raw'] ??
                      tx['value_raw'] ??
                      tx['raw_amount'] ??
                      tx['value'] ??
                      tx['amount'])
                  ?.toString() ??
              '0',
          'fee': tx['fee']?.toString(),
          'op_type':
              (tx['op_type'] ?? tx['type'] ?? tx['tx_type'])?.toString() ??
                  'standard',
          'status': (tx['status'] ??
                      tx['state'] ??
                      tx['tx_status'] ??
                      tx['final_status'])
                  ?.toString() ??
              'confirmed',
          'block_hash': tx['block_hash']?.toString(),
          'json_raw': jsonEncode(tx),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Retrieve paginated tx history for a wallet, newest first.
  Future<List<Map<String, dynamic>>> getTxHistory(
    String walletId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await database;
    return db.query(
      'tx_history',
      where: 'wallet_id = ?',
      whereArgs: [walletId],
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );
  }

  /// Get a single transaction by hash.
  Future<Map<String, dynamic>?> getTx(String walletId, String hash) async {
    final db = await database;
    final rows = await db.query(
      'tx_history',
      where: 'wallet_id = ? AND hash = ?',
      whereArgs: [walletId, hash],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> clearTxHistory(String walletId) async {
    final db = await database;
    await db
        .delete('tx_history', where: 'wallet_id = ?', whereArgs: [walletId]);
  }

  // ── Balance cache ──────────────────────────────────────────────────────────

  Future<void> cacheBalance({
    required String walletId,
    required String balanceRaw,
    required int nonce,
    String? encryptedBalance,
  }) async {
    final db = await database;
    await db.insert(
      'balance_cache',
      {
        'wallet_id': walletId,
        'balance_raw': balanceRaw,
        'nonce': nonce,
        'encrypted_balance': encryptedBalance,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, dynamic>?> getCachedBalance(String walletId) async {
    final db = await database;
    final rows = await db.query(
      'balance_cache',
      where: 'wallet_id = ?',
      whereArgs: [walletId],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  // ── Address book ───────────────────────────────────────────────────────────

  Future<void> addAddress({
    required String walletId,
    required String address,
    String? label,
    String? note,
  }) async {
    final db = await database;
    await db.insert(
      'address_book',
      {
        'wallet_id': walletId,
        'address': address,
        'label': label,
        'note': note,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAddressBook(String walletId) async {
    final db = await database;
    return db.query(
      'address_book',
      where: 'wallet_id = ?',
      whereArgs: [walletId],
      orderBy: 'created_at DESC',
    );
  }

  Future<void> deleteAddress(int id) async {
    final db = await database;
    await db.delete('address_book', where: 'id = ?', whereArgs: [id]);
  }

  // ── Token cache ────────────────────────────────────────────────────────────

  /// Saves a list of token balance maps for the given wallet.
  Future<void> cacheTokens(
      String walletId, List<Map<String, dynamic>> tokens) async {
    final db = await database;
    await db.insert(
      'token_cache',
      {
        'wallet_id': walletId,
        'tokens_json': jsonEncode(tokens),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Loads cached token balances for a wallet.
  /// Returns empty list if no cache or cache is older than [maxAgeMs] (default 5 min).
  Future<List<Map<String, dynamic>>> getCachedTokens(
    String walletId, {
    int maxAgeMs = 300000,
  }) async {
    final db = await database;
    final rows = await db.query(
      'token_cache',
      where: 'wallet_id = ?',
      whereArgs: [walletId],
      limit: 1,
    );
    if (rows.isEmpty) return [];
    final row = rows.first;
    final updatedAt = row['updated_at'] as int? ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - updatedAt;
    if (maxAgeMs > 0 && age > maxAgeMs) return []; // stale
    try {
      final list = jsonDecode(row['tokens_json'] as String? ?? '[]') as List;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  /// Clears the token cache for a given wallet.
  Future<void> clearTokenCache(String walletId) async {
    final db = await database;
    await db
        .delete('token_cache', where: 'wallet_id = ?', whereArgs: [walletId]);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static int _parseTs(dynamic ts) {
    if (ts == null) return 0;
    if (ts is int) return ts;
    if (ts is double) {
      // Normalise: Unix seconds → ms (same logic as string branch below).
      return ts > 1e12 ? ts.toInt() : (ts * 1000).toInt();
    }
    final d = double.tryParse(ts.toString());
    if (d != null) {
      // if seconds (< year 10000), convert to ms
      return d > 1e12 ? d.toInt() : (d * 1000).toInt();
    }
    return 0;
  }
}
