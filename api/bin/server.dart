import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:termin_api/router.dart';

void main(List<String> args) async {
  final ip = InternetAddress.anyIPv4;
  final store = SqliteStore.open(
    Platform.environment['DB_PATH'] ?? 'termin.db',
  );
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addHandler(buildRouter(store: store).call);

  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await serve(handler, ip, port);
  print('Server listening on port ${server.port}');
}
