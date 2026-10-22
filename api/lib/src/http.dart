import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

const _json = {'content-type': 'application/json'};

/// Largest accepted JSON request body, in bytes.
const maxJsonBytes = 4 * 1024;

Response jsonResponse(Object? body, {int status = 200}) =>
    Response(status, body: jsonEncode(body), headers: _json);

Response errorResponse(int status, String message) =>
    jsonResponse({'error': message}, status: status);

/// The request body exceeded the limit it was read with.
class BodyTooLarge implements Exception {}

/// Reads the body, throwing [BodyTooLarge] once it exceeds [maxBytes]
/// instead of buffering all of it.
Future<Uint8List> readBodyLimited(Request request, int maxBytes) async {
  final contentLength = request.contentLength;
  if (contentLength != null && contentLength > maxBytes) throw BodyTooLarge();
  final builder = BytesBuilder(copy: false);
  await for (final chunk in request.read()) {
    builder.add(chunk);
    if (builder.length > maxBytes) throw BodyTooLarge();
  }
  return builder.takeBytes();
}

/// Reads the body as a JSON object, or returns null if it isn't one.
///
/// Throws [BodyTooLarge] past [maxJsonBytes].
Future<Map<String, dynamic>?> readJsonObject(Request request) async {
  final bytes = await readBodyLimited(request, maxJsonBytes);
  try {
    final body = jsonDecode(utf8.decode(bytes));
    return body is Map<String, dynamic> ? body : null;
  } on FormatException {
    return null;
  }
}

/// A rate-limiting key for the client: its IP address, or its /64 for IPv6
/// since one host usually controls a whole /64.
///
/// With [trustProxy], uses the last `X-Forwarded-For` entry (the one the
/// reverse proxy appended) instead of the socket address.
String clientKey(Request request, {required bool trustProxy}) {
  String? raw;
  if (trustProxy) {
    raw = request.headers['x-forwarded-for']?.split(',').last.trim();
  } else {
    final info = request.context['shelf.io.connection_info'];
    if (info is HttpConnectionInfo) raw = info.remoteAddress.address;
  }
  final address = raw == null ? null : InternetAddress.tryParse(raw);
  if (address == null) return 'unknown';
  if (address.type == InternetAddressType.IPv6) {
    return InternetAddress.fromRawAddress(
      Uint8List.fromList([...address.rawAddress.take(8), ...Uint8List(8)]),
    ).address;
  }
  return address.address;
}
