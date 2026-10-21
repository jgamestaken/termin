import 'dart:convert';
import 'dart:typed_data';

import 'base64url.dart';

/// Ed25519 public key length in bytes.
const int publicKeyLength = 32;

/// Prefix signed together with a challenge, so a signature made for login
/// can't be replayed as a signature for anything else.
const String authSignatureDomain = 'termin-auth-v1\n';

/// The exact bytes a client signs with its Ed25519 key to answer [challenge].
Uint8List authSignaturePayload(List<int> challenge) =>
    Uint8List.fromList([...utf8.encode(authSignatureDomain), ...challenge]);

/// `POST /auth/challenge` body.
class ChallengeRequest {
  const ChallengeRequest({required this.publicKey});

  factory ChallengeRequest.fromJson(Map<String, dynamic> json) =>
      ChallengeRequest(publicKey: decodeBase64Url(json['publicKey'] as String));

  final Uint8List publicKey;

  Map<String, dynamic> toJson() => {'publicKey': encodeBase64Url(publicKey)};
}

/// `POST /auth/challenge` response.
class ChallengeResponse {
  const ChallengeResponse({required this.challenge, required this.expiresAt});

  factory ChallengeResponse.fromJson(Map<String, dynamic> json) =>
      ChallengeResponse(
        challenge: decodeBase64Url(json['challenge'] as String),
        expiresAt: DateTime.parse(json['expiresAt'] as String),
      );

  final Uint8List challenge;
  final DateTime expiresAt;

  Map<String, dynamic> toJson() => {
    'challenge': encodeBase64Url(challenge),
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };
}

/// `POST /auth/token` body: the challenge signed with the identity key.
class TokenRequest {
  const TokenRequest({
    required this.publicKey,
    required this.challenge,
    required this.signature,
  });

  factory TokenRequest.fromJson(Map<String, dynamic> json) => TokenRequest(
    publicKey: decodeBase64Url(json['publicKey'] as String),
    challenge: decodeBase64Url(json['challenge'] as String),
    signature: decodeBase64Url(json['signature'] as String),
  );

  final Uint8List publicKey;
  final Uint8List challenge;
  final Uint8List signature;

  Map<String, dynamic> toJson() => {
    'publicKey': encodeBase64Url(publicKey),
    'challenge': encodeBase64Url(challenge),
    'signature': encodeBase64Url(signature),
  };
}

/// `POST /auth/token` response. Send [token] as `Authorization: Bearer`.
class TokenResponse {
  const TokenResponse({required this.token, required this.expiresAt});

  factory TokenResponse.fromJson(Map<String, dynamic> json) => TokenResponse(
    token: json['token'] as String,
    expiresAt: DateTime.parse(json['expiresAt'] as String),
  );

  final String token;
  final DateTime expiresAt;

  Map<String, dynamic> toJson() => {
    'token': token,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
  };
}
