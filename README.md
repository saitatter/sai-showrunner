<p align="center">
  <img src="docs/branding/showrunner-icon-mark.svg" alt="ShowRunner" width="128" height="128">
</p>

<h1 align="center">ShowRunner</h1>

<p align="center">
  A production workspace for streamers and live creators.
</p>

<p align="center">
  <a href="https://github.com/saitatter/sai-showrunner/actions/workflows/ci.yml"><img src="https://github.com/saitatter/sai-showrunner/actions/workflows/ci.yml/badge.svg" alt="Build"></a>
  <a href="https://github.com/saitatter/sai-showrunner/releases"><img src="https://img.shields.io/github/v/release/saitatter/sai-showrunner" alt="Latest release"></a>
  <a href="LICENSE.md"><img src="https://img.shields.io/badge/License-AGPL--3.0-blue.svg" alt="AGPL-3.0 license"></a>
  <img src="https://img.shields.io/badge/Made%20with-Flutter-02569B?logo=flutter&logoColor=white" alt="Made with Flutter">
  <img src="https://img.shields.io/badge/Platform-Windows-lightgrey" alt="Windows">
</p>

ShowRunner brings stream control, visual automations, OBS, Twitch, YouTube,
overlays, queues, profiles, and production tools into one workspace. It is
designed for creators who want to prepare a show, connect their services, and
run the whole broadcast from one place.

## 📸 Demo

<p align="center">
  <em>Demo screenshots and GIFs will be added here.</em>
</p>

<!--
Suggested demo assets:

<p align="center">
  <img src="docs/images/showrunner-dashboard.png" alt="ShowRunner dashboard" width="48%">
  <img src="docs/images/showrunner-automation-editor.png" alt="ShowRunner automation editor" width="48%">
</p>
-->

## ✨ What you can do

- ⚡ Build visual automations with conditions, variables, reusable sections, and
  queues.
- 🔌 Connect Twitch, YouTube, OBS, moderation, sound, lighting, remote
  controls, and other production services.
- 🎬 Organize broadcasts with profiles and segmented Stream Plans.
- 🎨 Create browser overlays for OBS, including shader-driven effects made in
  the visual Shader Graph editor powered by [SAI Nodes](https://github.com/saitatter/sai_nodes).
- 📊 Manage connection health, live state, diagnostics, updates, and resources
  from the same workspace.

## 🚀 ShowRunner features beyond CastMate

ShowRunner is based on the [CastMate](https://github.com/LordTocs/CastMate)
project, but it is developed as its own product and desktop experience.
Compared with the public CastMate feature surface, ShowRunner includes or
targets these additional workflows:

- **Shader Graph overlays** — visual shader editing for procedural noise and
  terrain, lighting, camera and material effects, generated shaders, and
  automation-driven controls.
- **YouTube workflows** — live chat, memberships, paid messages, and matching
  overlay and automation starters alongside Twitch workflows.
- **Segmented Stream Plans** — reusable broadcast segments with separate start
  and stop automations.
- **Automation queues** — controlled sequencing for alerts, sounds, scenes, and
  other actions.
- **Local media assets** — sound, image, and video selection for overlays and
  playback without a separate media-management application.
- **Production dashboards** — connection health, stream plans, queue state, and
  live-service status in one view.
- **Remote and Satellite control** — trigger and monitor ShowRunner through its
  remote control protocol.
- **SAI services and moderation** — ShowRunner-specific services and moderation
  workflows connected to automations.
- **Expanded integrations** — including Bluesky, DonorDrive, Elgato, Govee,
  LIFX, TP-Link/Kasa, Twinkly, Wyze, Voicemod, Aitum, ADVSS, HTTP, IoT,
  operating-system, and input controls in addition to the core streaming
  integrations.

Optional CastMate plugins may overlap with individual integrations. The
important distinction is that these workflows are maintained as part of
ShowRunner itself.

## 🔄 Differences from CastMate

- ShowRunner uses a Flutter desktop application instead of CastMate's Electron
  desktop application.
- The desktop experience is organized around ShowRunner's visual graph editor,
  profiles, Stream Plans, queues, and production workspaces.
- ShowRunner has its own supported integrations, remote controls, data model,
  and release process.
- OBS overlay rendering remains browser-based because OBS consumes overlays as
  Browser Sources. The desktop app manages their resources, configuration, and
  events; the browser package renders them.

The original Electron/Vue implementation is kept only as a frozen product
reference for parity checks. It is not part of the current desktop runtime.

## 📦 Download

Windows releases are available on the
[GitHub Releases page](https://github.com/saitatter/sai-showrunner/releases).
The current release target is Windows and downloaded builds may show a
SmartScreen warning while signing is not yet configured.

## 🛠️ Run locally

The desktop application is developed from `packages/showrunner-flutter`:

```powershell
Push-Location .\packages\showrunner-flutter
flutter pub get
flutter run -d windows
Pop-Location
```

To validate the desktop app:

```powershell
Push-Location .\packages\showrunner-flutter
flutter analyze
flutter test
flutter build windows --release
Pop-Location
```

Node.js and Yarn are only needed when changing the browser overlay runtime:

```powershell
corepack enable
yarn install
yarn overlay:test
yarn overlay:build
```

The Windows package can be built and smoke-tested with:

```powershell
.\scripts\package-flutter-windows.ps1 -Version 1.0.0-beta1
```

## 🗂️ Repository layout

- 🖥️ `packages/showrunner-flutter` — the Flutter desktop application.
- 🌐 `packages/showrunner-obs-overlay` — the browser runtime loaded by OBS.
- 🧩 `plugins/*/overlay` and `libs/*overlay*` — reusable overlay widgets and
  protocol packages.
- 📚 `docs` — product, parity, and contributor documentation.

## 📄 License

ShowRunner is distributed under the [AGPL-3.0 license](LICENSE.md) and retains
the upstream CastMate license notices.
