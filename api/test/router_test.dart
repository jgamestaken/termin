import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:termin_api/router.dart';
import 'package:termin_core/termin_core.dart';
import 'package:test/test.dart';

void main() {
  final handler = buildRouter(store: SqliteStore.inMemory()).call;

  test('GET /health', () async {
    final response = await handler(
      Request('GET', Uri.parse('http://localhost/health')),
    );
    expect(response.statusCode, 200);
    final body = jsonDecode(await response.readAsString());
    expect(body, {'status': 'ok', 'apiVersion': apiVersion});
  });
}
