import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:termin_core/termin_core.dart';

import 'src/auth.dart';
import 'src/blobs.dart';
import 'src/store.dart';

export 'src/sqlite_store.dart';
export 'src/store.dart';

/// With [trustProxy], client addresses for rate limiting come from the last
/// `X-Forwarded-For` entry. Only set it behind a proxy that appends one.
Router buildRouter({
  required Store store,
  DateTime Function()? clock,
  bool trustProxy = false,
}) {
  clock ??= () => DateTime.now().toUtc();
  final auth = Auth(store, clock, trustProxy: trustProxy);
  final blobs = Blobs(store, clock);
  Handler authed(Handler handler) => auth.middleware(handler);

  return Router()
    ..get('/health', _health)
    ..post('/auth/challenge', auth.challenge)
    ..post('/auth/token', auth.token)
    ..get('/blobs', authed(blobs.list))
    ..get('/blobs/<id>', authed(blobs.get))
    ..put('/blobs/<id>', authed(blobs.put))
    ..delete('/blobs/<id>', authed(blobs.delete));
}

Response _health(Request request) => Response.ok(
  jsonEncode({'status': 'ok', 'apiVersion': apiVersion}),
  headers: {'content-type': 'application/json'},
);
