import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:termin_api/router.dart';

void main(List<String> args) async {
  final ip = InternetAddress.anyIPv4;
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addHandler(buildRouter().call);

  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await serve(handler, ip, port);
  print('Server listening on port ${server.port}');
}
