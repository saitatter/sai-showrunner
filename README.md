# ShowRunner

[![Build](https://github.com/saitatter/sai-showrunner/actions/workflows/ci.yml/badge.svg)](https://github.com/saitatter/sai-showrunner/actions/workflows/ci.yml)
[![GitHub Release](https://img.shields.io/github/v/release/saitatter/sai-showrunner)](https://github.com/saitatter/sai-showrunner/releases)
[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](LICENSE.md)
[![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey)](https://github.com/saitatter/sai-showrunner)

ShowRunner is a Windows broadcaster production suite for Twitch, YouTube, OBS,
overlays, stream automations, queues, and SAI services.

The desktop application is Flutter/Dart. Automations are graph documents using
`schemaVersion: 2`; the runtime accepts that schema directly and rejects other
document shapes. OBS browser sources are delivered by the small browser-overlay
runtime in `packages/showrunner-obs-overlay`.

## Quick start

```powershell
Push-Location .\packages\showrunner-flutter
flutter pub get
flutter run -d windows
Pop-Location
```

Validate the application:

```powershell
Push-Location .\packages\showrunner-flutter
flutter analyze
flutter test
flutter build windows --release
Pop-Location
```

Create and smoke-test a versioned archive:

```powershell
.\scripts\package-flutter-windows.ps1 -Version 1.0.0-beta1
```

The archive is written to `release/ShowRunner-Flutter-windows-<version>.zip`.
The smoke suite covers startup, first run, automation, workflow execution,
profiles, integrations, overlays, and updates. It uses an isolated user data
directory and does not modify `user/`.

## Application surface

- graph editor with subgraphs, data wires, variables, conditions, queues, and
  debugger feedback;
- Twitch, YouTube, OBS, moderation, remote, sound, input, lighting, resource,
  profile, and stream-plan workspaces;
- profile activation/deactivation graphs and event-triggered graph execution;
- overlay resource editing and OBS browser-source configuration;
- Windows packaging, update checks, diagnostics, and first-run setup.

## Browser overlay boundary

OBS browser sources require an HTML runtime. The browser overlay is therefore a
separate product surface and is built with `yarn overlay:build`; it consumes the
overlay protocol and resources produced by the Flutter application. It does not
provide a second desktop application or a second automation runtime.

## Optional overlay development

Node.js and Yarn are only needed when changing the browser overlay:

```powershell
corepack enable
yarn install
yarn overlay:test
yarn overlay:build
```

The Flutter app itself is developed, tested, and packaged from
`packages/showrunner-flutter`.

## Data and release notes

Runtime data lives in `user/` during local development and in the platform data
directory for packaged builds. Keep those directories when preserving a local
installation; generated Flutter build folders are disposable.

Windows is the supported release target. Builds are currently unsigned, so
SmartScreen may show a warning for downloaded artifacts.

ShowRunner is distributed under AGPL-3.0 and retains the upstream CastMate
license notices.
