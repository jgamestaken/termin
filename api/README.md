# termin_api

Sync API for Termin. Stores only client-side encrypted data. See the root README and CLAUDE.md.

```sh
dart run api/bin/server.dart   # from repo root, PORT defaults to 8080
(cd api && dart test)
```

Configuration: `PORT` (default `8080`) and `DB_PATH`, the SQLite file (default `termin.db`; `/data/termin.db` in Docker, mount a volume there).

## Endpoints

Request/response shapes live in `termin_core`. Binary values are base64url without padding.

There are no accounts. A client's identity is an Ed25519 public key, and its first login creates the user.

| Endpoint | Description |
|---|---|
| `GET /health` | Status and `apiVersion`. |
| `POST /auth/challenge` | `{publicKey}` → `{challenge, expiresAt}`. The challenge is single use and valid for 60 s. |
| `POST /auth/token` | `{publicKey, challenge, signature}` → `{token, expiresAt}`. The signature covers `authSignaturePayload(challenge)`. The token is valid for 7 days. |
| `GET /blobs` | Metadata for all of the caller's blobs, tombstones included. |
| `GET /blobs/<id>` | Raw ciphertext, with `ETag: "<version>"`. |
| `PUT /blobs/<id>` | Raw body (max 1 MiB). Send `If-None-Match: *` to create or `If-Match: "<version>"` to replace or revive. Returns 412 on a version mismatch, 428 without a precondition header, and 413 when the blob is too large or the caller already has 1000 live blobs. |
| `DELETE /blobs/<id>` | Requires `If-Match`. Leaves a tombstone. |

Every `/blobs` request needs `Authorization: Bearer <token>`.
