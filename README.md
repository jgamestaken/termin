# Termin

Cross-platform terminal app (Windows, Linux, macOS, iOS/iPadOS, Android) for quick access to your servers, with optional end-to-end encrypted sync and machine sharing.

## Layout

| Path | What |
| --- | --- |
| `apps/termin` | Flutter app |
| `api` | Dart (Shelf) sync API — stores only client-side encrypted data |
| `packages/termin_core` | Pure-Dart models and API contracts shared by app and API |

This is a [Dart pub workspace](https://dart.dev/tools/pub/workspaces): run `flutter pub get` once at the root.

## Quick start

```sh
flutter pub get                      # resolve the whole workspace
cd apps/termin && flutter run        # run the app
dart run api/bin/server.dart         # run the API on :8080 (PORT to override)
docker build -f api/Dockerfile .     # API container (build from repo root)
```
