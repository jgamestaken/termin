import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:termin_api/src/auth.dart';
import 'package:termin_api/src/http.dart';
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

  test('a failed attempt does not burn the challenge', () async {
    final challenge = (await api.challenge(publicKey)).challenge;
    expect(await requestToken(challenge, Uint8List(64)), 401);
    expect(await requestToken(challenge, await sign(keyPair, challenge)), 200);
  });

  test('rejects a tampered or foreign challenge', () async {
    final challenge = (await api.challenge(publicKey)).challenge;
    for (final index in [0, 16, challenge.length - 1]) {
      final tampered = Uint8List.fromList(challenge);
      tampered[index] ^= 1;
      expect(
        await requestToken(tampered, await sign(keyPair, tampered)),
        401,
        reason: 'byte $index',
      );
    }
    final random = Uint8List(32);
    expect(await requestToken(random, await sign(keyPair, random)), 401);

    // Another server instance has its own MAC key.
    final foreign = (await TestApi().challenge(publicKey)).challenge;
    expect(await requestToken(foreign, await sign(keyPair, foreign)), 401);
  });

  test('a flood of challenges does not block logins', () async {
    final other = await publicKeyOf(await Ed25519().newKeyPair());
    for (var i = 0; i < 20000; i++) {
      await api.send(
        'POST',
        '/auth/challenge',
        body: ChallengeRequest(publicKey: other).toJson(),
      );
    }
    expect((await api.tryLogin(keyPair)).statusCode, 200);
  });

  test('rejects oversized auth bodies', () async {
    final big = {'publicKey': 'A' * maxJsonBytes};
    for (final path in ['/auth/challenge', '/auth/token']) {
      expect((await api.send('POST', path, body: big)).statusCode, 413);
      final streamed = await api.send(
        'POST',
        path,
        body: Stream.fromIterable([Uint8List(maxJsonBytes), Uint8List(1)]),
      );
      expect(streamed.statusCode, 413, reason: '$path streamed');
    }
  });

  test('limits new users per client address', () async {
    final existing = await Ed25519().newKeyPair();
    expect((await api.tryLogin(existing)).statusCode, 200);
    for (var i = 1; i < Auth.signupsPerHour; i++) {
      expect((await api.tryLogin()).statusCode, 200, reason: 'signup $i');
    }
    expect((await api.tryLogin()).statusCode, 429);
    // Existing users can still log in.
    expect((await api.tryLogin(existing)).statusCode, 200);

    api.now = api.now.add(const Duration(hours: 1));
    expect((await api.tryLogin()).statusCode, 200);
  });

  test('with trustProxy, limits by the last X-Forwarded-For entry', () async {
    api = TestApi(trustProxy: true);
    Future<int> signup(String forwardedFor) async => (await api.tryLogin(null, {
      'x-forwarded-for': forwardedFor,
    })).statusCode;

    for (var i = 0; i < Auth.signupsPerHour; i++) {
      // The client-supplied first entry varies and must be ignored.
      expect(await signup('10.0.0.$i, 192.0.2.1'), 200);
    }
    expect(await signup('10.0.0.99, 192.0.2.1'), 429);
    expect(await signup('192.0.2.2'), 200);

    // IPv6 clients are limited per /64.
    for (var i = 0; i < Auth.signupsPerHour; i++) {
      expect(await signup('2001:db8::$i'), 200);
    }
    expect(await signup('2001:db8::ffff'), 429);
    expect(await signup('2001:db8:0:1::1'), 200);
  });

  test('keeps only the newest sessions per user', () async {
    final tokens = [
      for (var i = 0; i <= Auth.maxSessionsPerUser; i++)
        await api.login(keyPair),
    ];
    Future<int> status(String token) async =>
        (await api.send('GET', '/blobs', headers: bearer(token))).statusCode;
    expect(await status(tokens.first), 401);
    expect(await status(tokens[1]), 200);
    expect(await status(tokens.last), 200);
  });

  test('limits logins per user', () async {
    for (var i = 0; i < Auth.loginsPerHour; i++) {
      expect((await api.tryLogin(keyPair)).statusCode, 200, reason: '$i');
    }
    expect((await api.tryLogin(keyPair)).statusCode, 429);
    // Other users are unaffected.
    expect((await api.tryLogin()).statusCode, 200);

    api.now = api.now.add(const Duration(hours: 1));
    expect((await api.tryLogin(keyPair)).statusCode, 200);
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
