import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:termin_api/router.dart';

void main(List<String> args) async {
  final env = Platform.environment;
  final ip = InternetAddress.anyIPv4;
  final store = SqliteStore.open(
    env['DB_PATH'] ?? 'termin.db',
    maxTotalBytes: int.parse(env['MAX_STORAGE_BYTES'] ?? '${1 << 30}'),
  );
  final trustProxy = env['TRUST_PROXY'] == 'true';
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addHandler(buildRouter(store: store, trustProxy: trustProxy).call);

  final port = int.parse(env['PORT'] ?? '8080');
  final server = await serve(handler, ip, port);
  print('Server listening on port ${server.port}');
}
