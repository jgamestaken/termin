# termin_api

Sync API for Termin. Stores only client-side encrypted data. See the root README and CLAUDE.md.

```sh
dart run api/bin/server.dart   # from repo root, PORT defaults to 8080
(cd api && dart test)
```

Configuration:

- `PORT`: default `8080`.
- `DB_PATH`: the SQLite file. Default `termin.db`; `/data/termin.db` in Docker, mount a volume there.
- `MAX_STORAGE_BYTES`: server-wide limit on stored blob bytes, default 1 GiB. Writes past it get `507`.
- `TRUST_PROXY`: set to `true` behind a reverse proxy so rate limits use the last `X-Forwarded-For` entry instead of the proxy's address. Only enable it if the proxy always appends that header, or clients can spoof their address.

Serve it behind TLS: bearer tokens must not travel over plain HTTP.

## Endpoints

Request/response shapes live in `termin_core`. Binary values are base64url without padding.

There are no accounts. A client's identity is an Ed25519 public key, and its first login creates the user.

| Endpoint | Description |
|---|---|
| `GET /health` | Status and `apiVersion`. |
| `POST /auth/challenge` | `{publicKey}` → `{challenge, expiresAt}`. The challenge is opaque, single use and valid for 60 s. |
| `POST /auth/token` | `{publicKey, challenge, signature}` → `{token, expiresAt}`. The signature covers `authSignaturePayload(challenge)`. The token is valid for 7 days. Returns 429 after 30 logins by this user, or 10 new users from this client address, in the last hour. Each user keeps at most 20 sessions; logging in past that ends the oldest. |
| `GET /blobs` | Metadata for all of the caller's blobs, tombstones included. Only the newest 1000 tombstones are kept, so treat a previously synced blob that is missing here as deleted. |
| `GET /blobs/<id>` | Raw ciphertext, with `ETag: "<version>"`. |
| `PUT /blobs/<id>` | Raw body (max 1 MiB). Send `If-None-Match: *` to create or `If-Match: "<version>"` to replace or revive. Returns 412 on a version mismatch, 428 without a precondition header, 413 when the blob is too large or the caller would exceed 1000 live blobs or 1 MiB in total, and 507 when the server's storage limit is reached. |
| `DELETE /blobs/<id>` | Requires `If-Match`. Leaves a tombstone. |

Every `/blobs` request needs `Authorization: Bearer <token>`. JSON request bodies are limited to 4 KiB (413).
