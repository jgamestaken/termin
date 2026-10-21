import 'dart:convert';

import 'package:shelf/shelf.dart';

const _json = {'content-type': 'application/json'};

Response jsonResponse(Object? body, {int status = 200}) =>
    Response(status, body: jsonEncode(body), headers: _json);

Response errorResponse(int status, String message) =>
    jsonResponse({'error': message}, status: status);

/// Reads the body as a JSON object, or returns null if it isn't one.
Future<Map<String, dynamic>?> readJsonObject(Request request) async {
  try {
    final body = jsonDecode(await request.readAsString());
    return body is Map<String, dynamic> ? body : null;
  } on FormatException {
    return null;
  }
}
