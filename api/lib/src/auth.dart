import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:shelf/shelf.dart';
import 'package:termin_core/termin_core.dart';

import 'http.dart';
import 'rate_limit.dart';
import 'store.dart';

const _ownerKey = 'termin.owner';

/// The authenticated owner (base64url public key) set by [Auth.middleware].
extension RequestOwner on Request {
  String get owner => context[_ownerKey]! as String;
}

/// Challenge/response login with Ed25519 identity keys, and bearer sessions.
///
/// There is no signup step: the first successful login creates the user.
///
/// Challenges are stateless: each carries its expiry and an HMAC over it and
/// the public key it was issued for, so issuing one stores nothing. Only
/// challenges that were successfully answered are remembered, until they
/// expire, to keep them single use.
class Auth {
  Auth(this._store, this._clock, {required this._trustProxy})
    : _signups = RateLimiter(
        limit: signupsPerHour,
        window: const Duration(hours: 1),
        clock: _clock,
      ),
      _logins = RateLimiter(
        limit: loginsPerHour,
        window: const Duration(hours: 1),
        clock: _clock,
      );

  static const challengeTtl = Duration(seconds: 60);
  static const sessionTtl = Duration(days: 7);

  /// New users a single client address may create per hour.
  static const signupsPerHour = 10;

  /// Logins a single user may make per hour.
  static const loginsPerHour = 30;

  /// Sessions kept per user. Logging in past this ends the oldest one.
  static const maxSessionsPerUser = 20;

  static const _nonceLength = 16;
  static const _expiryLength = 8;
  static const _macLength = 32;
  static const _challengeLength = _nonceLength + _expiryLength + _macLength;

  final Store _store;
  final DateTime Function() _clock;
  final bool _trustProxy;
  final RateLimiter _signups;
  final RateLimiter _logins;
  static final _random = Random.secure();
  static final _hmac = Hmac.sha256();

  /// Per-process key for challenge MACs. A restart only invalidates logins
  /// that are in flight.
  final _challengeKey = SecretKey(_randomBytes(32));

  /// Answered challenges (base64url) and when they expire.
  final _usedChallenges = <String, DateTime>{};

  static Uint8List _randomBytes(int length) =>
      Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));

  static Future<Uint8List> _hash(List<int> bytes) async =>
      Uint8List.fromList((await Sha256().hash(bytes)).bytes);

  Future<Mac> _challengeMac(List<int> publicKey, List<int> nonceAndExpiry) =>
      _hmac.calculateMac([
        ...publicKey,
        ...nonceAndExpiry,
      ], secretKey: _challengeKey);

  /// `POST /auth/challenge`
  Future<Response> challenge(Request request) async {
    final ChallengeRequest body;
    try {
      body = ChallengeRequest.fromJson((await readJsonObject(request))!);
    } on BodyTooLarge {
      return errorResponse(413, 'request too large');
    } on Object {
      return errorResponse(400, 'invalid request');
    }
    if (body.publicKey.length != publicKeyLength) {
      return errorResponse(400, 'invalid public key');
    }

    final expiresAt = _clock().add(challengeTtl);
    final nonceAndExpiry = Uint8List(_nonceLength + _expiryLength)
      ..setAll(0, _randomBytes(_nonceLength));
    ByteData.sublistView(
      nonceAndExpiry,
      _nonceLength,
    ).setInt64(0, expiresAt.millisecondsSinceEpoch);
    final mac = await _challengeMac(body.publicKey, nonceAndExpiry);
    return jsonResponse(
      ChallengeResponse(
        challenge: Uint8List.fromList([...nonceAndExpiry, ...mac.bytes]),
        expiresAt: expiresAt,
      ).toJson(),
    );
  }

  /// When [challenge] expires, if it is an unused, unexpired challenge this
  /// server issued for [publicKey]. Otherwise null.
  Future<DateTime?> _checkChallenge(
    Uint8List publicKey,
    Uint8List challenge,
    DateTime now,
  ) async {
    if (challenge.length != _challengeLength) return null;
    const macOffset = _nonceLength + _expiryLength;
    final expected = await _challengeMac(
      publicKey,
      challenge.sublist(0, macOffset),
    );
    if (Mac(challenge.sublist(macOffset)) != expected) return null;
    // Only parse the expiry once the MAC shows this server wrote it.
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      ByteData.sublistView(challenge, _nonceLength).getInt64(0),
      isUtc: true,
    );
    if (!expiresAt.isAfter(now)) return null;
    if (_usedChallenges.containsKey(encodeBase64Url(challenge))) return null;
    return expiresAt;
  }

  /// `POST /auth/token`
  Future<Response> token(Request request) async {
    final TokenRequest body;
    try {
      body = TokenRequest.fromJson((await readJsonObject(request))!);
    } on BodyTooLarge {
      return errorResponse(413, 'request too large');
    } on Object {
      return errorResponse(400, 'invalid request');
    }

    final now = _clock();
    _usedChallenges.removeWhere((_, expiresAt) => !expiresAt.isAfter(now));
    final challengeExpiresAt = body.publicKey.length == publicKeyLength
        ? await _checkChallenge(body.publicKey, body.challenge, now)
        : null;
    if (challengeExpiresAt == null ||
        body.signature.length != 64 ||
        !await _verify(body)) {
      return errorResponse(401, 'authentication failed');
    }
    _usedChallenges[encodeBase64Url(body.challenge)] = challengeExpiresAt;

    // Counted only after the signature checks out, so nobody else can use
    // up a user's logins.
    final owner = encodeBase64Url(body.publicKey);
    if (!_logins.allow(owner)) {
      return errorResponse(429, 'too many logins, try again later');
    }
    if (!await _store.userExists(owner) &&
        !_signups.allow(clientKey(request, trustProxy: _trustProxy))) {
      return errorResponse(429, 'too many new accounts, try again later');
    }
    await _store.upsertUser(owner, now);
    await _store.deleteExpiredSessions(now);
    final token = _randomBytes(32);
    final expiresAt = now.add(sessionTtl);
    await _store.insertSession(
      await _hash(token),
      owner,
      expiresAt,
      maxPerOwner: maxSessionsPerUser,
    );
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
