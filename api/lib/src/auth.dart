import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:shelf/shelf.dart';
import 'package:termin_core/termin_core.dart';

import 'http.dart';
import 'store.dart';

const _ownerKey = 'termin.owner';

/// The authenticated owner (base64url public key) set by [Auth.middleware].
extension RequestOwner on Request {
  String get owner => context[_ownerKey]! as String;
}

/// Challenge/response login with Ed25519 identity keys, and bearer sessions.
///
/// There is no signup step: the first successful login creates the user.
class Auth {
  Auth(this._store, this._clock);

  static const challengeTtl = Duration(seconds: 60);
  static const sessionTtl = Duration(days: 7);
  static const _maxPendingChallenges = 10000;

  final Store _store;
  final DateTime Function() _clock;
  final _random = Random.secure();

  /// Outstanding challenges, keyed by base64url challenge.
  final _challenges = <String, ({String owner, DateTime expiresAt})>{};

  Uint8List _randomBytes(int length) =>
      Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));

  static Future<Uint8List> _hash(List<int> bytes) async =>
      Uint8List.fromList((await Sha256().hash(bytes)).bytes);

  /// `POST /auth/challenge`
  Future<Response> challenge(Request request) async {
    final ChallengeRequest body;
    try {
      body = ChallengeRequest.fromJson((await readJsonObject(request))!);
    } on Object {
      return errorResponse(400, 'invalid request');
    }
    if (body.publicKey.length != publicKeyLength) {
      return errorResponse(400, 'invalid public key');
    }

    final now = _clock();
    _challenges.removeWhere((_, c) => !c.expiresAt.isAfter(now));
    if (_challenges.length >= _maxPendingChallenges) {
      return errorResponse(503, 'too many pending logins');
    }

    final challenge = _randomBytes(32);
    final expiresAt = now.add(challengeTtl);
    _challenges[encodeBase64Url(challenge)] = (
      owner: encodeBase64Url(body.publicKey),
      expiresAt: expiresAt,
    );
    return jsonResponse(
      ChallengeResponse(challenge: challenge, expiresAt: expiresAt).toJson(),
    );
  }

  /// `POST /auth/token`
  Future<Response> token(Request request) async {
    final TokenRequest body;
    try {
      body = TokenRequest.fromJson((await readJsonObject(request))!);
    } on Object {
      return errorResponse(400, 'invalid request');
    }

    final now = _clock();
    final owner = encodeBase64Url(body.publicKey);
    // Single use: consumed whether or not the signature checks out.
    final pending = _challenges.remove(encodeBase64Url(body.challenge));
    if (pending == null ||
        pending.owner != owner ||
        !pending.expiresAt.isAfter(now) ||
        body.signature.length != 64 ||
        !await _verify(body)) {
      return errorResponse(401, 'authentication failed');
    }

    await _store.upsertUser(owner, now);
    await _store.deleteExpiredSessions(now);
    final token = _randomBytes(32);
    final expiresAt = now.add(sessionTtl);
    await _store.insertSession(await _hash(token), owner, expiresAt);
    return jsonResponse(
      TokenResponse(
        token: encodeBase64Url(token),
        expiresAt: expiresAt,
      ).toJson(),
    );
  }

  static Future<bool> _verify(TokenRequest body) => Ed25519().verify(
    authSignaturePayload(body.challenge),
    signature: Signature(
      body.signature,
      publicKey: SimplePublicKey(body.publicKey, type: KeyPairType.ed25519),
    ),
  );

  /// Rejects requests without a valid `Authorization: Bearer` session.
  Middleware get middleware =>
      (inner) => (request) async {
        final header = request.headers['authorization'];
        const prefix = 'Bearer ';
        if (header == null || !header.startsWith(prefix)) {
          return errorResponse(401, 'missing bearer token');
        }
        final Uint8List token;
        try {
          token = decodeBase64Url(header.substring(prefix.length).trim());
        } on FormatException {
          return errorResponse(401, 'invalid bearer token');
        }
        final owner = await _store.findSession(await _hash(token), _clock());
        if (owner == null) return errorResponse(401, 'invalid bearer token');
        return inner(request.change(context: {_ownerKey: owner}));
      };
}
