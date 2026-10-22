import 'dart:io';
import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';
import 'package:termin_api/router.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late String path;
  final now = DateTime.utc(2026, 10, 21);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('termin_store_test');
    path = '${dir.path}/termin.db';
  });

  tearDown(() => dir.delete(recursive: true));

  test('migrates v1 databases and counts existing bytes', () async {
    sqlite3.open(path)
      ..execute('''
        CREATE TABLE users (public_key TEXT PRIMARY KEY, created_at INTEGER NOT NULL);
        CREATE TABLE sessions (token_hash BLOB PRIMARY KEY, owner TEXT NOT NULL, expires_at INTEGER NOT NULL);
        CREATE TABLE blobs (
          owner TEXT NOT NULL, id TEXT NOT NULL, version INTEGER NOT NULL,
          data BLOB, updated_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (owner, id)
        );
        INSERT INTO users VALUES ('u', 0);
        INSERT INTO blobs VALUES ('u', 'a', 1, zeroblob(60), 0, 0);
        INSERT INTO blobs VALUES ('u', 'b', 2, NULL, 0, 1);
        PRAGMA user_version = 1;
      ''')
      ..close();

    final store = SqliteStore.open(path, maxTotalBytes: 100);
    addTearDown(store.close);
    await expectLater(
      store.putBlob('u', 'c', Uint8List(41), ifMatch: null, now: now),
      throwsA(isA<StorageFull>()),
    );
    await store.putBlob('u', 'c', Uint8List(40), ifMatch: null, now: now);
  });

  test('the server-wide total survives a reopen', () async {
    var store = SqliteStore.open(path);
    await store.upsertUser('u', now);
    await store.putBlob('u', 'a', Uint8List(60), ifMatch: null, now: now);
    await store.close();

    store = SqliteStore.open(path, maxTotalBytes: 100);
    addTearDown(store.close);
    await expectLater(
      store.putBlob('u', 'b', Uint8List(41), ifMatch: null, now: now),
      throwsA(isA<StorageFull>()),
    );
  });
}
