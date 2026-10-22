import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:termin_core/termin_core.dart';

import 'auth.dart';
import 'http.dart';
import 'store.dart';

/// Handlers for `/blobs`. All require [Auth.middleware].
class Blobs {
  Blobs(this._store, this._clock);

  final Store _store;
  final DateTime Function() _clock;

  static final _etag = RegExp(r'^"(\d+)"$');

  static String _etagFor(int version) => '"$version"';

  static String? _id(Request request) {
    final id = request.params['id'];
    return id != null && blobIdPattern.hasMatch(id) ? id : null;
  }

  /// Parses `If-Match: "<version>"`. Null if absent, throws if malformed.
  static int? _ifMatch(Request request) {
    final header = request.headers['if-match'];
    if (header == null) return null;
    final match = _etag.firstMatch(header.trim());
    if (match == null) throw const FormatException();
    return int.parse(match.group(1)!);
  }

  /// `GET /blobs`
  Future<Response> list(Request request) async => jsonResponse([
    for (final meta in await _store.listBlobs(request.owner)) meta.toJson(),
  ]);

  /// `GET /blobs/<id>`
  Future<Response> get(Request request) async {
    final id = _id(request);
    if (id == null) return errorResponse(400, 'invalid blob id');
    final blob = await _store.getBlob(request.owner, id);
    if (blob == null) return errorResponse(404, 'not found');
    return Response.ok(
      blob.data,
      headers: {
        'content-type': 'application/octet-stream',
        'etag': _etagFor(blob.meta.version),
      },
    );
  }

  /// `PUT /blobs/<id>`: `If-None-Match: *` to create, `If-Match` to replace.
  Future<Response> put(Request request) async {
    final id = _id(request);
    if (id == null) return errorResponse(400, 'invalid blob id');

    final int? ifMatch;
    try {
      ifMatch = _ifMatch(request);
    } on FormatException {
      return errorResponse(400, 'invalid If-Match');
    }
    final createOnly = request.headers['if-none-match']?.trim() == '*';
    if ((ifMatch == null) == !createOnly) {
      return errorResponse(
        428,
        'send exactly one of If-Match or If-None-Match: *',
      );
    }

    final Uint8List data;
    try {
      data = await readBodyLimited(request, maxBlobBytes);
    } on BodyTooLarge {
      return errorResponse(413, 'blob too large');
    }

    try {
      final meta = await _store.putBlob(
        request.owner,
        id,
        data,
        ifMatch: ifMatch,
        now: _clock(),
      );
      return jsonResponse(meta.toJson())
          .change(headers: {'etag': _etagFor(meta.version)});
    } on PreconditionFailed {
      return errorResponse(412, 'version mismatch');
    } on QuotaExceeded {
      return errorResponse(413, 'quota exceeded');
    } on StorageFull {
      return errorResponse(507, 'server storage full');
    }
  }

  /// `DELETE /blobs/<id>` with `If-Match`. Leaves a tombstone.
  Future<Response> delete(Request request) async {
    final id = _id(request);
    if (id == null) return errorResponse(400, 'invalid blob id');

    final int? ifMatch;
    try {
      ifMatch = _ifMatch(request);
    } on FormatException {
      return errorResponse(400, 'invalid If-Match');
    }
    if (ifMatch == null) return errorResponse(428, 'If-Match required');

    try {
      await _store.deleteBlob(
        request.owner,
        id,
        ifMatch: ifMatch,
        now: _clock(),
      );
      return Response(204);
    } on BlobNotFound {
      return errorResponse(404, 'not found');
    } on PreconditionFailed {
      return errorResponse(412, 'version mismatch');
    }
  }
}
