import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:termin_core/termin_core.dart';
import 'package:test/test.dart';

import 'helpers.dart';

void main() {
  late TestApi api;
  late SimpleKeyPair keyPair;
  late Uint8List publicKey;

  setUp(() async {
    api = TestApi();
    keyPair = await Ed25519().newKeyPair();
    publicKey = await publicKeyOf(keyPair);
  });

  Future<int> requestToken(Uint8List challenge, Uint8List signature) async =>
      (await api.send(
        'POST',
        '/auth/token',
        body: TokenRequest(
          publicKey: publicKey,
          challenge: challenge,
          signature: signature,
        ).toJson(),
      )).statusCode;

  test('first login signs up and the token works', () async {
    final token = await api.login(keyPair);
    final response = await api.send('GET', '/blobs', headers: bearer(token));
    expect(response.statusCode, 200);
    expect(await readJson(response), isEmpty);
  });

  test('the same key gets the same identity on a second login', () async {
    final first = await api.login(keyPair);
    await api.send(
      'PUT',
      '/blobs/a',
      body: 'x',
      headers: {...bearer(first), 'if-none-match': '*'},
    );
    final second = await api.login(keyPair);
    final list = await readJson(
      await api.send('GET', '/blobs', headers: bearer(second)),
    );
    expect(list, hasLength(1));
  });

  test('rejects a bad signature', () async {
    final challenge = (await api.challenge(publicKey)).challenge;
    final other = await Ed25519().newKeyPair();
    expect(await requestToken(challenge, await sign(other, challenge)), 401);
  });

  test('rejects a challenge issued for another key', () async {
    final other = await Ed25519().newKeyPair();
    final challenge = (await api.challenge(await publicKeyOf(other))).challenge;
    expect(await requestToken(challenge, await sign(keyPair, challenge)), 401);
  });

  test('a challenge is single use', () async {
    final challenge = (await api.challenge(publicKey)).challenge;
    final signature = await sign(keyPair, challenge);
    expect(await requestToken(challenge, signature), 200);
    expect(await requestToken(challenge, signature), 401);
  });

  test('a failed attempt burns the challenge', () async {
    final challenge = (await api.challenge(publicKey)).challenge;
    expect(await requestToken(challenge, Uint8List(64)), 401);
    expect(await requestToken(challenge, await sign(keyPair, challenge)), 401);
  });

  test('rejects an expired challenge', () async {
    final challenge = (await api.challenge(publicKey)).challenge;
    api.now = api.now.add(const Duration(seconds: 61));
    expect(await requestToken(challenge, await sign(keyPair, challenge)), 401);
  });

  test('rejects an expired token', () async {
    final token = await api.login(keyPair);
    api.now = api.now.add(const Duration(days: 7));
    final response = await api.send('GET', '/blobs', headers: bearer(token));
    expect(response.statusCode, 401);
  });

  test('rejects malformed auth requests', () async {
    for (final body in [
      'not json',
      <String, dynamic>{},
      {'publicKey': '!!'},
      {'publicKey': encodeBase64Url(Uint8List(31))},
    ]) {
      final response = await api.send('POST', '/auth/challenge', body: body);
      expect(response.statusCode, 400, reason: '$body');
    }
    final response = await api.send('POST', '/auth/token', body: {'x': 1});
    expect(response.statusCode, 400);
  });

  test('rejects missing or unknown bearer tokens', () async {
    for (final headers in [
      <String, String>{},
      {'authorization': 'Basic abc'},
      {'authorization': 'Bearer !!!'},
      bearer(encodeBase64Url(Uint8List(32))),
    ]) {
      final response = await api.send('GET', '/blobs', headers: headers);
      expect(response.statusCode, 401, reason: '$headers');
    }
  });
}
