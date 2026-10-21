import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';
import 'package:termin_core/termin_core.dart';

import 'store.dart';

/// [Store] backed by a single SQLite database file.
class SqliteStore implements Store {
  SqliteStore._(this._db) {
    _db.execute('PRAGMA journal_mode = WAL');
    _db.execute('PRAGMA foreign_keys = ON');
    _migrate();
  }

  /// Opens (creating if needed) the database at [path].
  factory SqliteStore.open(String path) => SqliteStore._(sqlite3.open(path));

  factory SqliteStore.inMemory() => SqliteStore._(sqlite3.openInMemory());

  final Database _db;

  static const _migrations = [
    '''
    CREATE TABLE users (
      public_key TEXT PRIMARY KEY,
      created_at INTEGER NOT NULL
    );
    CREATE TABLE sessions (
      token_hash BLOB PRIMARY KEY,
      owner TEXT NOT NULL REFERENCES users(public_key),
      expires_at INTEGER NOT NULL
    );
    CREATE INDEX sessions_expires_at ON sessions(expires_at);
    CREATE TABLE blobs (
      owner TEXT NOT NULL REFERENCES users(public_key),
      id TEXT NOT NULL,
      version INTEGER NOT NULL,
      data BLOB,
      updated_at INTEGER NOT NULL,
      deleted INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (owner, id)
    );
    ''',
  ];

  void _migrate() {
    final current = _db.select('PRAGMA user_version').first.columnAt(0) as int;
    for (var v = current; v < _migrations.length; v++) {
      _transaction(() {
        _db.execute(_migrations[v]);
        _db.execute('PRAGMA user_version = ${v + 1}');
      });
    }
  }

  T _transaction<T>(T Function() body) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      final result = body();
      _db.execute('COMMIT');
      return result;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  static int _ms(DateTime t) => t.millisecondsSinceEpoch;
  static DateTime _time(int ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

  ({int version, bool deleted})? _current(String owner, String id) {
    final rows = _db.select(
      'SELECT version, deleted FROM blobs WHERE owner = ? AND id = ?',
      [owner, id],
    );
    if (rows.isEmpty) return null;
    return (
      version: rows.first['version'] as int,
      deleted: rows.first['deleted'] == 1,
    );
  }

  @override
  Future<void> upsertUser(String owner, DateTime now) async => _db.execute(
    'INSERT OR IGNORE INTO users (public_key, created_at) VALUES (?, ?)',
    [owner, _ms(now)],
  );

  @override
  Future<void> insertSession(
    Uint8List tokenHash,
    String owner,
    DateTime expiresAt,
  ) async => _db.execute(
    'INSERT INTO sessions (token_hash, owner, expires_at) VALUES (?, ?, ?)',
    [tokenHash, owner, _ms(expiresAt)],
  );

  @override
  Future<String?> findSession(Uint8List tokenHash, DateTime now) async {
    final rows = _db.select(
      'SELECT owner FROM sessions WHERE token_hash = ? AND expires_at > ?',
      [tokenHash, _ms(now)],
    );
    return rows.isEmpty ? null : rows.first['owner'] as String;
  }

  @override
  Future<void> deleteExpiredSessions(DateTime now) async =>
      _db.execute('DELETE FROM sessions WHERE expires_at <= ?', [_ms(now)]);

  @override
  Future<List<BlobMeta>> listBlobs(String owner) async => [
    for (final row in _db.select(
      'SELECT id, version, updated_at, deleted FROM blobs '
      'WHERE owner = ? ORDER BY id',
      [owner],
    ))
      BlobMeta(
        id: row['id'] as String,
        version: row['version'] as int,
        updatedAt: _time(row['updated_at'] as int),
        deleted: row['deleted'] == 1,
      ),
  ];

  @override
  Future<StoredBlob?> getBlob(String owner, String id) async {
    final rows = _db.select(
      'SELECT version, updated_at, data FROM blobs '
      'WHERE owner = ? AND id = ? AND deleted = 0',
      [owner, id],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return (
      meta: BlobMeta(
        id: id,
        version: row['version'] as int,
        updatedAt: _time(row['updated_at'] as int),
      ),
      data: row['data'] as Uint8List,
    );
  }

  @override
  Future<BlobMeta> putBlob(
    String owner,
    String id,
    Uint8List data, {
    required int? ifMatch,
    required DateTime now,
  }) async => _transaction(() {
    final current = _current(owner, id);
    if (current?.version != ifMatch) throw PreconditionFailed();
    if (current == null || current.deleted) {
      final live =
          _db
                  .select(
                    'SELECT COUNT(*) FROM blobs WHERE owner = ? AND deleted = 0',
                    [owner],
                  )
                  .first
                  .columnAt(0)
              as int;
      if (live >= maxBlobsPerUser) throw QuotaExceeded();
    }
    final version = (current?.version ?? 0) + 1;
    _db.execute(
      'INSERT INTO blobs (owner, id, version, data, updated_at, deleted) '
      'VALUES (?, ?, ?, ?, ?, 0) '
      'ON CONFLICT (owner, id) DO UPDATE SET version = excluded.version, '
      'data = excluded.data, updated_at = excluded.updated_at, deleted = 0',
      [owner, id, version, data, _ms(now)],
    );
    return BlobMeta(id: id, version: version, updatedAt: _time(_ms(now)));
  });

  @override
  Future<BlobMeta> deleteBlob(
    String owner,
    String id, {
    required int ifMatch,
    required DateTime now,
  }) async => _transaction(() {
    final current = _current(owner, id);
    if (current == null || current.deleted) throw BlobNotFound();
    if (current.version != ifMatch) throw PreconditionFailed();
    final version = current.version + 1;
    _db.execute(
      'UPDATE blobs SET version = ?, data = NULL, updated_at = ?, deleted = 1 '
      'WHERE owner = ? AND id = ?',
      [version, _ms(now), owner, id],
    );
    return BlobMeta(
      id: id,
      version: version,
      updatedAt: _time(_ms(now)),
      deleted: true,
    );
  });

  @override
  Future<void> close() async => _db.close();
}
