import 'dart:convert';
import 'dart:typed_data';

/// Encodes [bytes] as base64url without padding, the wire format for all
/// binary values in the API.
String encodeBase64Url(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// Decodes base64url with or without padding. Throws [FormatException].
Uint8List decodeBase64Url(String value) =>
    base64Url.decode(base64Url.normalize(value));
