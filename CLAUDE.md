# Termin

Cross-platform Flutter terminal app for quickly reaching your own servers (SSH etc.), plus a small sync API so users can keep and share machines across devices.

Targets: Windows, Linux, macOS, iOS/iPadOS, Android. Don't add the web platform. A raw-socket SSH client can't run in a browser.

## Repo layout (Dart pub workspace)

- `apps/termin`: Flutter app (package `termin`).
- `api`: Dart Shelf server (package `termin_api`). `bin/server.dart` is the entrypoint; routes live in `lib/`.
- `packages/termin_core`: pure-Dart code shared by the app and the API (models, DTOs, API contract). **No Flutter imports here**, because the API depends on it.
- Root `pubspec.yaml` is the workspace. Every member has `resolution: workspace`, and there's one `pubspec.lock` at the root. New packages go under `packages/` and must be added to the root `workspace:` list.

## Commands

Run from the repo root unless noted:

```sh
flutter pub get                          # resolve all packages (root only; no per-package lockfiles)
dart analyze                             # analyze the whole workspace
dart format .
(cd packages/termin_core && dart test)
(cd api && dart test)
(cd apps/termin && flutter test)
dart run api/bin/server.dart             # API on :8080, override with PORT
docker build -f api/Dockerfile .         # build context must be the repo root
```

## Security model (non-negotiable)

- **End-to-end encryption.** All user secrets (hosts, usernames, passwords, private keys, notes) are encrypted **in the app** before they leave the device. The API stores and returns only opaque ciphertext blobs plus the minimal metadata it needs for routing (ids, owner, timestamps, versions, share recipients).
- The API must never receive plaintext secrets or key material it could decrypt with. Don't add server-side decryption, "recovery" or search over secret fields.
- Sharing a machine means re-encrypting (or wrapping its key) for the recipient's public key on the client. The server only relays the wrapped key.
- Use well-reviewed primitives (e.g. libsodium/`cryptography` package: XChaCha20-Poly1305/AES-GCM, X25519, Argon2id for key derivation). Never write your own crypto. Never log secrets or ciphertext payloads.
- Local secrets on device go in platform secure storage (Keychain/Keystore/DPAPI/libsecret), not plain files or shared prefs.

## Conventions

- Lints: `flutter_lints` (app) and `lints` (Dart packages). Keep `dart analyze` clean.
- Anything both sides need (request/response shapes, `apiVersion`) goes in `termin_core`, not duplicated.
- Bump `apiVersion` in `termin_core` on breaking API contract changes.
- App id / bundle id: `net.jgamestaken.termin`.

## Status

Scaffolding only: a placeholder app screen and an API with just `GET /health`. Not chosen yet: state management, SSH/terminal libraries, storage backend for the API, and auth scheme. Ask before committing to one.
