import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:termin_core/termin_core.dart';

Router buildRouter() => Router()..get('/health', _health);

Response _health(Request request) => Response.ok(
  jsonEncode({'status': 'ok', 'apiVersion': apiVersion}),
  headers: {'content-type': 'application/json'},
);
