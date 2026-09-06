# ShowRunner

[![Build](https://github.com/saitatter/sai-showrunner/actions/workflows/ci.yml/badge.svg)](https://github.com/saitatter/sai-showrunner/actions/workflows/ci.yml)
[![GitHub Release](https://img.shields.io/github/v/release/saitatter/sai-showrunner)](https://github.com/saitatter/sai-showrunner/releases)
[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](LICENSE.md)
[![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey)](https://github.com/saitatter/sai-showrunner)

ShowRunner is a Windows production suite for streamers and live creators. It
brings OBS, Twitch, YouTube, overlays, automations, queues, profiles, and SAI
services together in one application.

Create visual automations, connect your live services, prepare reusable show
profiles, and control your stream from one place. OBS overlays are managed from
the app and displayed through a small browser companion that OBS can load.

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

## What you can do

- build visual automations with conditions, variables, queues, and reusable
  sections;
- connect Twitch, YouTube, OBS, moderation, sound, lighting, remote controls,
  and other production tools;
- organize profiles and stream plans for different shows or broadcasts;
- create and manage browser overlays for OBS, including shader-driven effects
  built with a visual Shader Graph editor;
- keep projects, settings, diagnostics, and updates in one Windows app.

## Browser overlay boundary

OBS loads overlays as browser sources, so the overlay display is provided by a
small companion package while the desktop app manages the overlay content and
events. It is not a second desktop application.

## Differences from CastMate upstream

The upstream project is [CastMate](https://github.com/LordTocs/CastMate). This
repository is a ShowRunner fork and Flutter replacement implementation; `main`
is only the frozen local product reference used by parity checks. The main
product differences are intentional:

- ShowRunner uses a Flutter desktop app instead of CastMate's Electron desktop
  app;
- ShowRunner focuses on visual graph automations rather than a separate Timeline
  editor;
- ShowRunner uses one current project format and does not automatically convert
  older CastMate project files;
- the supported integrations and remote controls are organized around
  ShowRunner's own app and companion services;
- OBS overlays remain browser-based so they work naturally as OBS browser
  sources.

These differences keep the supported live-production workflows while giving
ShowRunner its own desktop experience.

## Optional overlay development

Node.js and Yarn are only needed when changing the browser overlay:

```powershell
corepack enable
yarn install
yarn overlay:test
yarn overlay:build
```

The Flutter app itself is developed, tested, and packaged from
`packages/showrunner-flutter`. Contributor and architecture notes are in
`DEVELOPERS.md`.

## Data and release notes

Runtime data lives in `user/` during local development and in the platform data
directory for packaged builds. Keep those directories when preserving a local
installation; generated Flutter build folders are disposable.

Windows is the supported release target. Builds are currently unsigned, so
SmartScreen may show a warning for downloaded artifacts.

ShowRunner is distributed under AGPL-3.0 and retains the upstream CastMate
license notices.
