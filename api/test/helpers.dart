import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:shelf/shelf.dart';
import 'package:termin_api/router.dart';
import 'package:termin_core/termin_core.dart';

/// A router over an in-memory store with a controllable clock.
class TestApi {
  TestApi({int? maxTotalBytes, bool trustProxy = false})
    : store = SqliteStore.inMemory(maxTotalBytes: maxTotalBytes) {
    handler = buildRouter(
      store: store,
      clock: () => now,
      trustProxy: trustProxy,
    ).call;
  }

  final SqliteStore store;
  DateTime now = DateTime.utc(2026, 10, 21, 12);
  late final Handler handler;

  Future<Response> send(
    String method,
    String path, {
    Object? body,
    Map<String, String> headers = const {},
  }) async => handler(
    Request(
      method,
      Uri.parse('http://localhost$path'),
      body: body is Map || (body is List && body is! Uint8List)
          ? jsonEncode(body)
          : body,
      headers: headers,
    ),
  );

  Future<ChallengeResponse> challenge(Uint8List publicKey) async {
    final response = await send(
      'POST',
      '/auth/challenge',
      body: ChallengeRequest(publicKey: publicKey).toJson(),
    );
    return ChallengeResponse.fromJson(await readJson(response));
  }

  /// Logs in with a fresh or given identity and returns the response.
  Future<Response> tryLogin([
    SimpleKeyPair? keyPair,
    Map<String, String> headers = const {},
  ]) async {
    keyPair ??= await Ed25519().newKeyPair();
    final publicKey = await publicKeyOf(keyPair);
    final challenge = await this.challenge(publicKey);
    return send(
      'POST',
      '/auth/token',
      body: TokenRequest(
        publicKey: publicKey,
        challenge: challenge.challenge,
        signature: await sign(keyPair, challenge.challenge),
      ).toJson(),
      headers: headers,
    );
  }

  /// Logs in with a fresh or given identity and returns a bearer token.
  Future<String> login([SimpleKeyPair? keyPair]) async =>
      TokenResponse.fromJson(await readJson(await tryLogin(keyPair))).token;
}

Future<Uint8List> publicKeyOf(SimpleKeyPair keyPair) async =>
    Uint8List.fromList((await keyPair.extractPublicKey()).bytes);

Future<Uint8List> sign(SimpleKeyPair keyPair, Uint8List challenge) async =>
    Uint8List.fromList(
      (await Ed25519().sign(
        authSignaturePayload(challenge),
        keyPair: keyPair,
      )).bytes,
    );

Future<dynamic> readJson(Response response) async =>
    jsonDecode(await response.readAsString());

Map<String, String> bearer(String token) => {'authorization': 'Bearer $token'};
