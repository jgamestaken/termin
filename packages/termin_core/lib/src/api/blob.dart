/// Allowed blob ids. Clients should use random ids (e.g. UUIDs) so the id
/// itself reveals nothing.
final RegExp blobIdPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// Largest accepted blob body, in bytes.
const int maxBlobBytes = 1024 * 1024;

/// Most live (non-deleted) blobs a single user may hold.
const int maxBlobsPerUser = 1000;

/// Most bytes of live blobs a single user may hold.
const int maxBytesPerUser = 32 * 1024 * 1024;

/// Server-side metadata for a blob. The content itself is opaque ciphertext.
class BlobMeta {
  const BlobMeta({
    required this.id,
    required this.version,
    required this.updatedAt,
    this.deleted = false,
  });

  factory BlobMeta.fromJson(Map<String, dynamic> json) => BlobMeta(
    id: json['id'] as String,
    version: json['version'] as int,
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    deleted: json['deleted'] as bool? ?? false,
  );

  final String id;

  /// Incremented on every write and delete. Send as `If-Match: "<version>"`.
  final int version;
  final DateTime updatedAt;

  /// Tombstone: the blob was deleted, kept so other devices see the deletion.
  final bool deleted;

  Map<String, dynamic> toJson() => {
    'id': id,
    'version': version,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'deleted': deleted,
  };

  @override
  bool operator ==(Object other) =>
      other is BlobMeta &&
      other.id == id &&
      other.version == version &&
      other.updatedAt == updatedAt &&
      other.deleted == deleted;

  @override
  int get hashCode => Object.hash(id, version, updatedAt, deleted);
}
