# ShowRunner Flutter

The Windows-first Flutter renderer and Dart runtime migration workspace for ShowRunner.

## Local validation

Run these commands from this directory:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

The application reads and writes the existing ShowRunner user data directory. Keep a
separate test profile or backup when exercising persistence and provider OAuth flows.

## Scope

The package includes the Flutter shell, graph adapter, automation and profile catalogs,
queue and diagnostics workspaces, resource editors, provider workers, and Dart plugin
contracts. OBS overlays remain browser-based because OBS consumes them as browser sources.

Migration status and release gates are tracked in `docs/flutter-migration-plan.md`.
