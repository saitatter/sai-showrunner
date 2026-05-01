# ShowRunner

[![Build](https://github.com/saitatter/sai-showrunner/actions/workflows/ci.yml/badge.svg)](https://github.com/saitatter/sai-showrunner/actions/workflows/ci.yml)
[![GitHub Release](https://img.shields.io/github/v/release/saitatter/sai-showrunner)](https://github.com/saitatter/sai-showrunner/releases)
[![Issues](https://img.shields.io/github/issues/saitatter/sai-showrunner)](https://github.com/saitatter/sai-showrunner/issues)
[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](LICENSE.md)
![Made with Electron](https://img.shields.io/badge/Made%20with-Electron-47848F?logo=electron&logoColor=white)
![Vue](https://img.shields.io/badge/Vue-3-4FC08D?logo=vuedotjs&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey)

> Desktop-first broadcaster production suite for Twitch, YouTube, OBS, overlays, stream automations, and SAI services.

ShowRunner is an AGPL-3.0 fork of CastMate. Upstream architecture, plugin boundaries, and license notices are preserved while the app is being shaped into the SAI streaming toolchain.

---

## Features

### Stream Integrations

- Twitch integration with profiles, channel point rewards, chat triggers, stream events, and automation actions.
- YouTube integration with browser OAuth, live chat ingest, chat command triggers, paid message triggers, membership triggers, author flags, and manual broadcast/live chat discovery.
- OBS WebSocket integration for scene/control actions and browser source workflows.
- SAI Moderation Docker integration with native ShowRunner queue/status UI and manual override actions.

### Automation Workflow

- Original CastMate timeline editor for detailed action sequencing.
- Node-based automation editor for graph-style trigger/action flows.
- Right-click command menu for triggers and actions with collapsible groups.
- Node-native operations for insert, duplicate, delete, reorder, fit view, snap, and preview.
- Trigger/action templates for moderated chat feeds, paid alerts, scene banners, and stream states.

### Overlay Studio

- OBS browser source URLs with copy/open controls and live presence indicators.
- Native `Chat Feed` widget for approved Twitch/YouTube messages.
- Native `Paid Alert` widget for YouTube paid messages, donations, and support events.
- Native `Scene Banner` widget for begin/end/intermission style overlays.
- Native `Shader Layer` widget with bundled WebGL presets, local shader presets, live params, and fallback rendering.
- Runtime overlay delivery through ShowRunner state/actions instead of direct Streamer.bot wiring.

### Moderation

- Native queue page under `Integrations -> Moderation`.
- Queue views for latest, pending, approved, and rejected messages.
- Search/filter by message, viewer, platform, and verdict.
- Automation action: `Moderation: Filter Chat Message`.
- Backend-compatible `deliveryMode: "decisionOnly"` flow for SAI Moderation Docker.

### Desktop UI

- CastMate-style production workspace with profiles, integrations, overlays, variables, media, audio, and automations.
- ShowRunner branding, taskbar icon, and first-run setup flow.
- Activity/log surfaces for integration errors and successful operations.
- In-app update support using GitHub Releases and Electron updater metadata.

---

## Quick Start

### Run from source

```powershell
corepack enable
corepack yarn install
corepack yarn dev
```

### Build all Vite targets

```powershell
node .\vite-util\multi-vite.mjs build
```

### Build a local Windows installer

```powershell
$env:CSC_IDENTITY_AUTO_DISCOVERY = "false"
corepack yarn build
```

Generated Windows artifacts are written to `release/`.

---

## Clean YouTube Test Run

Use this when you want a clean local app data folder and explicit YouTube OAuth credentials:

```powershell
corepack yarn dev:clean:youtube -- -YouTubeClientId "your-client-id.apps.googleusercontent.com" -YouTubeClientSecret "your-client-secret"
```

Release builds can bundle YouTube credentials with:

| Setting | Source |
|---------|--------|
| `SHOWRUNNER_YOUTUBE_CLIENT_ID` | repository variable |
| `SHOWRUNNER_YOUTUBE_CLIENT_SECRET` | repository secret |

---

## First Run Setup

Recommended setup order:

1. Open `Integrations -> Twitch -> Account Login` and connect Channel/Bot accounts.
2. Open `Integrations -> YouTube -> Live Integration`, confirm the OAuth checklist, then connect YouTube.
3. Open `Integrations -> OBS` and configure OBS WebSocket.
4. Open `Integrations -> Moderation -> Moderation Docker`, choose `Localhost`, save, run Health, then Send Test Event.
5. Create or open an overlay, copy the Browser Source URL, and add it to OBS.
6. Add a `Chat Feed`, `Paid Alert`, `Scene Banner`, or `Shader Layer` widget in Overlay Studio.
7. Create an automation and use `Nodes` mode for graph workflows or `Timeline` for the upstream detailed editor.

---

## Automation Templates

Ready-made templates are available under `Automations`:

| Template | Use case |
|----------|----------|
| `Template: Twitch Moderated Chat Feed` | Twitch chat -> moderation -> chat feed |
| `Template: YouTube Moderated Chat Feed` | YouTube chat -> moderation -> chat feed |
| `Template: Approved Only Chat Feed` | Push already-approved messages to a target chat widget |
| `Template: YouTube Paid Alert` | Super Chat / Super Sticker -> paid alert |
| `Template: Twitch Paid Alert` | subs / bits / channel points -> paid alert |
| `Template: Scene Banner` | scene begin/end automation |
| `Template: Starting Soon / BRB / Ending` | common stream-state overlays |

Recommended moderated chat flow:

```text
Twitch/YouTube chat trigger
-> Moderation: Filter Chat Message
-> condition on approved/verdict
-> Overlays: Push Chat Message
-> Chat Feed widget
```

`Filter Chat Message` sends `deliveryMode: "decisionOnly"` to `POST /v1/chat-events`, so moderation updates the queue and returns a verdict without publishing directly to an overlay.

---

## Moderation Docker

ShowRunner can use SAI Moderation Docker as a backend-only moderation service. The old docker-hosted `/dashboard` page remains available for compatibility, but the primary queue UI is native in ShowRunner.

Default URLs:

| Service | URL |
|---------|-----|
| API | `http://localhost:8787` |
| Dashboard WebSocket | `ws://localhost:8787/ws?channel=dashboard` |

In the app, open:

```text
Integrations -> Moderation -> Moderation Docker
```

Enable the integration, verify health, send a test event, and leave `Forward YouTube chat` enabled if you want YouTube messages to enter the moderation pipeline automatically.

---

## Overlay Widgets

| Widget | Purpose |
|--------|---------|
| `Chat Feed` | Configurable approved chat widget with platform colors, font sizing, opacity, fade time, max messages, layout, badges, and targeted delivery |
| `Paid Alert` | Targeted support-event widget for YouTube paid messages, donations, and future providers |
| `Scene Banner` | Begin/end/intermission style scene messaging |
| `Shader Layer` | WebGL widget with bundled presets, local saved presets, custom fragment shader editor mode, color/intensity/speed controls, opacity/blend mode, and fallback state |

The older standalone `sai-chat-overlay` flow can be retired once your ShowRunner overlay contains a `Chat Feed` widget and automations push approved messages with `Overlays -> Push Chat Message`.

---

## Automation Editor

Open or create an automation:

```text
Automations -> New/Open Automation
```

The editor starts in `Nodes` mode. Use:

- left click to select a node
- right click to open the command menu for triggers and actions
- drag to organize nodes visually
- `Timeline` toggle for the legacy detailed editor

Node editor controls:

- drag actions from the palette onto the canvas
- drop actions on an edge to insert them between nodes
- middle mouse drag pans the canvas
- `Ctrl + wheel` zooms
- `F` fits the graph
- `Ctrl + D` duplicates the selected node
- `Delete` removes the selected node

---

## Releases

Uses **semantic-release** with Conventional Commits. On every push to `main`, CI checks if a new version should be published.

- Use Conventional Commits: `feat: ...`, `fix: ...`, `chore: ...`
- Use scopes for readable release notes: `feat(youtube): ...`, `fix(overlays): ...`
- Breaking changes: use `!` or a `BREAKING CHANGE:` footer
- Main is protected by a repository ruleset; work should happen on feature branches and land through PRs
- GitHub squash commits are expanded so release notes include each conventional commit from the PR branch
- Windows installer, update metadata, blockmap, and zip assets are attached to GitHub Releases

Release notes use the same category model as `pylrcget`:

| Section | Commit types |
|---------|--------------|
| Features | `feat` |
| Fixes | `fix`, `perf` |
| Refactors | `refactor` |
| CI & Build | `build`, `ci`, `chore` |
| Docs | `docs` |
| Tests | `test` |

### Windows note

Windows release builds are currently unsigned. SmartScreen may show a warning on newly downloaded builds. Continue through `More info` -> `Run anyway` only if you trust the release source.

### In-app updates

ShowRunner checks GitHub Releases for newer versions and uses Electron updater metadata when available.

| Platform | Supported assets |
|----------|------------------|
| Windows | `SAI.Showrunner-<version>-x64.exe`, `latest.yml`, `.blockmap`, `.zip` |

---

## Troubleshooting

- **YouTube login is blocked** - Add your Google account as a tester in the OAuth consent screen while the app is in testing mode.
- **No active YouTube broadcast found** - Use manual Broadcast ID / Live Chat ID discovery in the YouTube integration page.
- **Moderation queue is empty** - Check that SAI Moderation Docker is running on port `8787` and that the integration is enabled.
- **OBS overlay does not update** - Verify the Browser Source URL is loaded in OBS and the overlay presence indicator is connected.
- **SmartScreen warning on Windows** - See [Windows note](#windows-note).

---

## Contributing

PRs are welcome. Please:

- keep commits small and conventional
- preserve upstream CastMate license notices
- run `corepack yarn check` before submitting TypeScript/Vue changes
- use feature branches instead of committing directly to `main`

---

## Upstream

ShowRunner is based on CastMate by LordTocs:

https://github.com/LordTocs/CastMate

---

## License

AGPL-3.0. See [LICENSE.md](LICENSE.md).
