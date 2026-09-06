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
with Quick and Full scan modes plus a debounced filesystem watcher. Metadata
extraction remains an explicit follow-up for formats that need native TagLib
support. OBS overlays remain browser-based because OBS consumes them as browser
sources.

Run `dart run tool/media_scan_benchmark.dart --files=1000` from this package to
measure first-scan and unchanged quick-scan behavior on the current machine.

All persisted automation documents use `schemaVersion: 2`. The loader rejects
other document shapes so the runtime and editor operate on one contract.
