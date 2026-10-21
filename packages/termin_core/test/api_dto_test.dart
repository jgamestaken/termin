import 'dart:convert';

import 'package:termin_core/termin_core.dart';
import 'package:test/test.dart';

void main() {
  test('base64url round-trips without padding', () {
    final bytes = List.generate(31, (i) => i * 7 % 256);
    final encoded = encodeBase64Url(bytes);
    expect(encoded, isNot(contains('=')));
    expect(decodeBase64Url(encoded), bytes);
  });

  test('authSignaturePayload is domain prefix + challenge', () {
    expect(authSignaturePayload([1, 2, 3]), [
      ...utf8.encode('termin-auth-v1\n'),
      1,
      2,
      3,
    ]);
  });

  test('TokenRequest round-trips through JSON', () {
    final request = TokenRequest(
      publicKey: decodeBase64Url(encodeBase64Url(List.filled(32, 1))),
      challenge: decodeBase64Url(encodeBase64Url(List.filled(32, 2))),
      signature: decodeBase64Url(encodeBase64Url(List.filled(64, 3))),
    );
    final decoded = TokenRequest.fromJson(
      jsonDecode(jsonEncode(request.toJson())) as Map<String, dynamic>,
    );
    expect(decoded.publicKey, request.publicKey);
    expect(decoded.challenge, request.challenge);
    expect(decoded.signature, request.signature);
  });

  test('BlobMeta round-trips through JSON', () {
    final meta = BlobMeta(
      id: 'abc_123',
      version: 4,
      updatedAt: DateTime.utc(2026, 10, 21, 12),
      deleted: true,
    );
    expect(
      BlobMeta.fromJson(
        jsonDecode(jsonEncode(meta.toJson())) as Map<String, dynamic>,
      ),
      meta,
    );
  });

  test('blobIdPattern', () {
    expect(blobIdPattern.hasMatch('a-B_9'), isTrue);
    expect(blobIdPattern.hasMatch(''), isFalse);
    expect(blobIdPattern.hasMatch('a/b'), isFalse);
    expect(blobIdPattern.hasMatch('x' * 65), isFalse);
  });
}
