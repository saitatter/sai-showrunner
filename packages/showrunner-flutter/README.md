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
and Dart plugin contracts. OBS overlays remain browser-based because OBS
consumes them as browser sources.

All persisted automation documents use `schemaVersion: 2`. The loader rejects
other document shapes so the runtime and editor operate on one contract.
