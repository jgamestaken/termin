import 'dart:typed_data';

import 'package:termin_core/termin_core.dart';

/// The blob's current version didn't match the request's precondition.
class PreconditionFailed implements Exception {}

/// Writing would exceed [maxBlobsPerUser] or [maxBytesPerUser].
class QuotaExceeded implements Exception {}

/// Writing would exceed the server-wide storage limit.
class StorageFull implements Exception {}

/// The blob doesn't exist (or is already deleted).
class BlobNotFound implements Exception {}

/// A live blob's metadata and ciphertext.
typedef StoredBlob = ({BlobMeta meta, Uint8List data});

/// Persistence for users, sessions and blobs.
///
/// Owners are identified by their base64url-encoded Ed25519 public key.
abstract interface class Store {
  Future<bool> userExists(String owner);

  /// Records [owner] if it hasn't been seen before.
  Future<void> upsertUser(String owner, DateTime now);

  /// Adds a session, then drops [owner]'s oldest sessions beyond
  /// [maxPerOwner].
  Future<void> insertSession(
    Uint8List tokenHash,
    String owner,
    DateTime expiresAt, {
    required int maxPerOwner,
  });

  /// The owner of an unexpired session with [tokenHash], or null.
  Future<String?> findSession(Uint8List tokenHash, DateTime now);

  Future<void> deleteExpiredSessions(DateTime now);

  /// All of [owner]'s blobs, tombstones included.
  Future<List<BlobMeta>> listBlobs(String owner);

  /// A live blob, or null if missing or deleted.
  Future<StoredBlob?> getBlob(String owner, String id);

  /// Creates ([ifMatch] null) or replaces ([ifMatch] = current version) a
  /// blob. Replacing a tombstone revives it.
  ///
  /// Throws [PreconditionFailed], [QuotaExceeded] or [StorageFull].
  Future<BlobMeta> putBlob(
    String owner,
    String id,
    Uint8List data, {
    required int? ifMatch,
    required DateTime now,
  });

  /// Turns a live blob into a tombstone, then drops [owner]'s oldest
  /// tombstones beyond [maxTombstonesPerUser].
  ///
  /// Throws [BlobNotFound] or [PreconditionFailed].
  Future<BlobMeta> deleteBlob(
    String owner,
    String id, {
    required int ifMatch,
    required DateTime now,
  });

  Future<void> close();
}
