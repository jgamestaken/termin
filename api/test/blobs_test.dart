import 'dart:typed_data';

import 'package:termin_core/termin_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late TestApi api;
  late String token;

  setUp(() async {
    api = TestApi();
    token = await api.login();
  });

  Future<int> put(
    String id,
    Object body, {
    String? ifMatch,
    bool create = false,
    String? as,
  }) async => (await api.send(
    'PUT',
    '/blobs/$id',
    body: body,
    headers: {
      ...bearer(as ?? token),
      'if-match': ?ifMatch,
      if (create) 'if-none-match': '*',
    },
  )).statusCode;

  Future<int> delete(String id, {String? ifMatch}) async => (await api.send(
    'DELETE',
    '/blobs/$id',
    headers: {...bearer(token), 'if-match': ?ifMatch},
  )).statusCode;

  Future<List<BlobMeta>> list() async => [
    for (final json in await readJson(
      await api.send('GET', '/blobs', headers: bearer(token)),
    ) as List)
      BlobMeta.fromJson(json as Map<String, dynamic>),
  ];

  test('create, read, replace', () async {
    final created = await api.send(
      'PUT',
      '/blobs/m1',
      body: Uint8List.fromList([1, 2, 3]),
      headers: {...bearer(token), 'if-none-match': '*'},
    );
    expect(created.statusCode, 200);
    expect(created.headers['etag'], '"1"');
    expect(
      BlobMeta.fromJson(await readJson(created)),
      BlobMeta(id: 'm1', version: 1, updatedAt: api.now),
    );

    var read = await api.send('GET', '/blobs/m1', headers: bearer(token));
    expect(read.statusCode, 200);
    expect(read.headers['etag'], '"1"');
    expect(read.headers['content-type'], 'application/octet-stream');
    expect(await read.read().expand((c) => c).toList(), [1, 2, 3]);

    expect(await put('m1', 'v2', ifMatch: '"1"'), 200);
    read = await api.send('GET', '/blobs/m1', headers: bearer(token));
    expect(read.headers['etag'], '"2"');
    expect(await read.readAsString(), 'v2');
  });

  test('version preconditions', () async {
    expect(await put('m1', 'a'), 428);
    expect(await put('m1', 'a', ifMatch: '"0"', create: true), 428);
    expect(await put('m1', 'a', ifMatch: '1'), 400);
    expect(await put('m1', 'a', ifMatch: '"1"'), 412);
    expect(await put('m1', 'a', create: true), 200);
    expect(await put('m1', 'b', create: true), 412);
    expect(await put('m1', 'b', ifMatch: '"2"'), 412);
    expect(await put('m1', 'b', ifMatch: '"1"'), 200);
    expect(await put('m1', 'c', ifMatch: '"1"'), 412);
  });

  test('delete leaves a tombstone that can be revived', () async {
    await put('m1', 'a', create: true);
    expect(await delete('m1'), 428);
    expect(await delete('m1', ifMatch: '"2"'), 412);
    expect(await delete('m1', ifMatch: '"1"'), 204);
    expect(await delete('m1', ifMatch: '"2"'), 404);

    final read = await api.send('GET', '/blobs/m1', headers: bearer(token));
    expect(read.statusCode, 404);
    expect(await list(), [
      BlobMeta(id: 'm1', version: 2, updatedAt: api.now, deleted: true),
    ]);

    expect(await put('m1', 'b', create: true), 412);
    expect(await put('m1', 'b', ifMatch: '"2"'), 200);
    expect(await list(), [BlobMeta(id: 'm1', version: 3, updatedAt: api.now)]);
  });

  test('rejects invalid ids', () async {
    expect(await put('a.b', 'x', create: true), 400);
    expect(await put('x' * 65, 'x', create: true), 400);
    final read = await api.send('GET', '/blobs/a.b', headers: bearer(token));
    expect(read.statusCode, 400);
  });

  test('rejects oversized blobs', () async {
    expect(await put('big', Uint8List(maxBlobBytes), create: true), 200);
    expect(await put('big2', Uint8List(maxBlobBytes + 1), create: true), 413);
    final streamed = await api.send(
      'PUT',
      '/blobs/big3',
      body: Stream.fromIterable([Uint8List(maxBlobBytes), Uint8List(1)]),
      headers: {...bearer(token), 'if-none-match': '*'},
    );
    expect(streamed.statusCode, 413);
  });

  test('enforces the per-user blob limit on live blobs', () async {
    for (var i = 0; i < maxBlobsPerUser; i++) {
      await put('b$i', 'x', create: true);
    }
    expect(await put('over', 'x', create: true), 413);
    expect(await put('b0', 'y', ifMatch: '"1"'), 200);
    expect(await delete('b1', ifMatch: '"1"'), 204);
    expect(await put('over', 'x', create: true), 200);
    expect(await put('b1', 'x', ifMatch: '"2"'), 413);
  });

  test('enforces the per-user byte limit on live blobs', () async {
    const count = maxBytesPerUser ~/ maxBlobBytes;
    for (var i = 0; i < count; i++) {
      expect(await put('b$i', Uint8List(maxBlobBytes), create: true), 200);
    }
    expect(await put('over', 'x', create: true), 413);
    // Shrinking is allowed, and frees room.
    expect(await put('b0', Uint8List(10), ifMatch: '"1"'), 200);
    expect(await put('over', 'x', create: true), 200);
    expect(await delete('b1', ifMatch: '"1"'), 204);
    expect(await put('b2', Uint8List(maxBlobBytes), ifMatch: '"1"'), 200);
    expect(await put('big', Uint8List(maxBlobBytes ~/ 2), create: true), 200);
  });

  test('enforces the server-wide byte limit', () async {
    api = TestApi(maxTotalBytes: 100);
    token = await api.login();
    final other = await api.login();
    expect(await put('a', Uint8List(60), create: true), 200);
    expect(await put('b', Uint8List(41), create: true, as: other), 507);
    expect(await put('b', Uint8List(40), create: true, as: other), 200);
    expect(await put('c', 'x', create: true), 507);
    expect(await delete('a', ifMatch: '"1"'), 204);
    expect(await put('c', Uint8List(60), create: true), 200);
  });

  test('users cannot see each other\'s blobs', () async {
    await put('m1', 'secret', create: true);
    final other = await api.login();

    final read = await api.send('GET', '/blobs/m1', headers: bearer(other));
    expect(read.statusCode, 404);
    final otherList = await api.send('GET', '/blobs', headers: bearer(other));
    expect(await readJson(otherList), isEmpty);
    expect(await put('m1', 'mine', ifMatch: '"1"', as: other), 412);

    // Same id, separate namespace.
    expect(await put('m1', 'mine', create: true, as: other), 200);
    final mine = await api.send('GET', '/blobs/m1', headers: bearer(token));
    expect(await mine.readAsString(), 'secret');
  });
}
