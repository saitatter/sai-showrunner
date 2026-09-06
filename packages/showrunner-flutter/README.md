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
and Dart plugin contracts. Overlay widgets include a Flutter Shader Graph
editor and compiler; OBS still displays the resulting browser source. Local
asset selection and sound playback remain available without a persistent media
catalog. OBS overlays remain browser-based because OBS consumes them as browser
sources.

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
- local asset selection is performed only when a resource is edited; there is no
  persistent media catalog or background filesystem scanner;
- OBS overlay rendering stays in the browser package because the consumer is
  an OBS Browser Source.

All persisted automation documents use `schemaVersion: 2`. The loader rejects
other document shapes so the runtime and editor operate on one contract.
