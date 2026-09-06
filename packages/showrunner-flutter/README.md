# ShowRunner Flutter

The Flutter/Dart desktop application for ShowRunner on Windows.

## Local validation

Run these commands from this directory:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

The application reads and writes the ShowRunner user data directory. Keep a
separate test profile or backup when exercising persistence and provider OAuth
flows.

## Scope

This package contains the Flutter shell, V2 graph editor, automation and profile
catalogs, queue and diagnostics workspaces, resource editors, provider workers,
and Dart plugin contracts. The media workspace uses a persistent SQLite index
with Quick and Full scan modes plus a debounced filesystem watcher. It indexes
filesystem state and does not include native TagLib metadata extraction; media
preview and playback use the existing `media_kit` boundary. OBS overlays remain
browser-based because OBS consumes them as browser sources.

## Differences from CastMate upstream

The upstream project is [CastMate](https://github.com/LordTocs/CastMate). The
frozen Electron/Vue `main` branch is only the local parity reference. Flutter
keeps the supported ShowRunner workflows but changes the implementation
boundaries:

- desktop UI and runtime are Flutter/Dart with typed contracts, explicit
  service ownership, and a centralized shutdown lifecycle instead of the
  Electron/Vue/Node desktop stack;
- automation persistence accepts V2 documents only and does not convert older
  CastMate document shapes or create automatic conversion backups;
- first-party plugins are compiled Dart modules; external plugin code is not
  loaded in-process, and remote control uses a versioned agent protocol;
- media indexing is SQLite-backed with fingerprinted quick scans, explicit full
  scans, and a debounced watcher, without native TagLib extraction;
- OBS overlay rendering stays in the browser package because the consumer is
  an OBS Browser Source.

Run `dart run tool/media_scan_benchmark.dart --files=1000` from this package to
measure first-scan and unchanged quick-scan behavior on the current machine.

All persisted automation documents use `schemaVersion: 2`. The loader rejects
other document shapes so the runtime and editor operate on one contract.
