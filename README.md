# ShowRunner

[![Build](https://github.com/saitatter/sai-showrunner/actions/workflows/ci.yml/badge.svg)](https://github.com/saitatter/sai-showrunner/actions/workflows/ci.yml)
[![GitHub Release](https://img.shields.io/github/v/release/saitatter/sai-showrunner)](https://github.com/saitatter/sai-showrunner/releases)
[![Issues](https://img.shields.io/github/issues/saitatter/sai-showrunner)](https://github.com/saitatter/sai-showrunner/issues)
[![License: AGPL-3.0](https://img.shields.io/badge/License-AGPL--3.0-blue.svg)](LICENSE.md)
![Made with Electron](https://img.shields.io/badge/Made%20with-Electron-47848F?logo=electron&logoColor=white)
![Vue](https://img.shields.io/badge/Vue-3-4FC08D?logo=vuedotjs&logoColor=white)
![TypeScript](https://img.shields.io/badge/TypeScript-5-3178C6?logo=typescript&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Windows-lightgrey)

> Desktop-first broadcaster production suite for Twitch, YouTube, OBS, overlays, stream automations, and SAI services.

ShowRunner is an AGPL-3.0 fork of [ShowRunner](https://github.com/LordTocs/ShowRunner). It preserves the upstream architecture, plugin boundaries, and license notices while shaping the app into the SAI streaming toolchain — adding YouTube integration, AI-powered moderation, an overlay studio, and a node-based automation editor.

---

## ✨ Features

### 🔌 Stream Integrations

- Twitch integration with profiles, channel point rewards, chat triggers, stream events, and automation actions
- YouTube integration with browser OAuth, live chat ingest, chat command triggers, paid message triggers, membership triggers, author flags, and manual broadcast/live chat discovery
- OBS WebSocket integration for scene/control actions and browser source workflows
- SAI Moderation Docker integration with native queue/status UI and manual override actions

### 🔀 Automation Workflow

- **Graph execution engine** — compiles node graphs to a flat instruction program (16 opcodes) and executes via a stack-based VM with abort support, yield scheduling, and subgraph calls
- Safe expression DSL (no `eval()`) with literals, variables, port references, binary/unary ops, member/index access, and 18 builtin functions
- Node-based automation editor for graph-style trigger/action flows with data wires and variable nodes
- Timeline editor for detailed action sequencing (upstream ShowRunner mode)
- Right-click command menu for triggers and actions with collapsible groups
- Node-native operations: insert, duplicate, delete, reorder, fit view, snap, preview
- Copy/paste support for nodes, variable nodes, and wires across automations
- Ready-made templates for moderated chat feeds, paid alerts, scene banners, and stream states

### 🎨 Overlay Studio

- OBS browser source URLs with copy/open controls and live presence indicators
- WebSocket reconnection hardening with duplicate-connect guard, status tracking, and safe-send checks
- Native `Chat Feed` widget for approved Twitch/YouTube messages
- Native `Paid Alert` widget for YouTube paid messages, donations, and support events
- Native `Scene Banner` widget for begin/end/intermission style overlays
- Native `Shader Layer` widget with bundled WebGL presets, local shader presets, live params, and fallback rendering
- Demo mode (`?demo=true`) and status indicator (`?statusVisible=true`) for overlay development
- Runtime overlay delivery through ShowRunner state/actions instead of direct Streamer.bot wiring

### 🛡️ Moderation

- Native queue page under `Integrations → Moderation`
- Queue views for latest, pending, approved, and rejected messages
- Search/filter by message, viewer, platform, and verdict
- Automation action: `Moderation: Filter Chat Message`
- Backend-compatible `deliveryMode: "decisionOnly"` flow for SAI Moderation Docker

### 🖥️ Desktop UI

- ShowRunner-style production workspace with profiles, integrations, overlays, variables, media, audio, and automations
- ShowRunner branding, taskbar icon, and first-run setup flow
- Activity/log surfaces for integration errors and successful operations
- In-app update support using GitHub Releases and Electron updater metadata

---

## 🚀 Quick Start

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

## 🧪 Clean YouTube Test Run

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

## 📋 First Run Setup

Recommended setup order:

1. Open `Integrations → Twitch → Account Login` and connect Channel/Bot accounts
2. Open `Integrations → YouTube → Live Integration`, confirm the OAuth checklist, then connect YouTube
3. Open `Integrations → OBS` and configure OBS WebSocket
4. Open `Integrations → Moderation → Moderation Docker`, choose `Localhost`, save, run Health, then Send Test Event
5. Create or open an overlay, copy the Browser Source URL, and add it to OBS
6. Add a `Chat Feed`, `Paid Alert`, `Scene Banner`, or `Shader Layer` widget in Overlay Studio
7. Create an automation and use `Nodes` mode for graph workflows or `Timeline` for the upstream detailed editor

---

## 📐 Automation Templates

Ready-made templates are available under `Automations`:

| Template | Use case |
|----------|----------|
| `Template: Twitch Moderated Chat Feed` | Twitch chat → moderation → chat feed |
| `Template: YouTube Moderated Chat Feed` | YouTube chat → moderation → chat feed |
| `Template: Approved Only Chat Feed` | Push already-approved messages to a target chat widget |
| `Template: YouTube Paid Alert` | Super Chat / Super Sticker → paid alert |
| `Template: Twitch Paid Alert` | Subs / bits / channel points → paid alert |
| `Template: Scene Banner` | Scene begin/end automation |
| `Template: Starting Soon / BRB / Ending` | Common stream-state overlays |

Recommended moderated chat flow:

```text
Twitch/YouTube chat trigger
  → Moderation: Filter Chat Message
  → condition on approved/verdict
  → Overlays: Push Chat Message
  → Chat Feed widget
```

`Filter Chat Message` sends `deliveryMode: "decisionOnly"` to `POST /v1/chat-events`, so moderation updates the queue and returns a verdict without publishing directly to an overlay.

---

## 🐳 Moderation Docker

ShowRunner can use SAI Moderation Docker as a backend-only moderation service. The old docker-hosted `/dashboard` page remains available for compatibility, but the primary queue UI is native in ShowRunner.

| Service | URL |
|---------|-----|
| API | `http://localhost:8787` |
| Dashboard WebSocket | `ws://localhost:8787/ws?channel=dashboard` |

In the app, open `Integrations → Moderation → Moderation Docker`, enable the integration, verify health, send a test event, and leave `Forward YouTube chat` enabled if you want YouTube messages to enter the moderation pipeline automatically.

---

## 🧩 Overlay Widgets

| Widget | Purpose |
|--------|---------|
| `Chat Feed` | Configurable approved chat widget with platform colors, font sizing, opacity, fade time, max messages, layout, badges, and targeted delivery |
| `Paid Alert` | Targeted support-event widget for YouTube paid messages, donations, and future providers |
| `Scene Banner` | Begin/end/intermission style scene messaging |
| `Shader Layer` | WebGL widget with bundled presets, local saved presets, custom fragment shader editor, color/intensity/speed controls, opacity/blend mode, and fallback state |

> **Note:** The older standalone `sai-chat-overlay` flow can be retired once your ShowRunner overlay contains a `Chat Feed` widget and automations push approved messages with `Overlays → Push Chat Message`.

---

## ✏️ Automation Editor

Open or create an automation via `Automations → New/Open Automation`. The editor starts in `Nodes` mode.

### Canvas controls

| Action | Input |
|--------|-------|
| Select node | Left click |
| Command menu (triggers & actions) | Right click |
| Move nodes | Drag |
| Pan canvas | Middle mouse drag |
| Zoom | `Ctrl` + scroll wheel |
| Fit graph | `F` |
| Duplicate node | `Ctrl + D` |
| Delete node | `Delete` |
| Copy / Cut / Paste | `Ctrl + C` / `Ctrl + X` / `Ctrl + V` |
| Toggle legacy timeline editor | `Timeline` button |

### Data wires & variable nodes

- Drag between output/input ports to create data wires
- Variable nodes store intermediate values and can be connected to any compatible port
- Double-click a variable node subtitle to rename it inline
- Circular dependency detection prevents invalid wire connections
- Connected ports show a solid dot indicator; wire deletion plays a red fade-out animation

---

## 🔄 Releases

Uses **semantic-release** with Conventional Commits. On every push to `main`, CI checks if a new version should be published.

- Use Conventional Commits: `feat: ...`, `fix: ...`, `chore: ...`
- Use scopes for readable release notes: `feat(youtube): ...`, `fix(overlays): ...`
- Breaking changes: use `!` or a `BREAKING CHANGE:` footer
- Main is protected by a repository ruleset; work on feature branches and land through PRs
- GitHub squash commits are expanded so release notes include each conventional commit from the PR branch

| Section | Commit types |
|---------|--------------|
| Features | `feat` |
| Fixes | `fix`, `perf` |
| Refactors | `refactor` |
| CI & Build | `build`, `ci`, `chore` |
| Docs | `docs` |
| Tests | `test` |

### 🛡️ Windows note

Windows release builds are currently unsigned. SmartScreen may show a warning on newly downloaded builds — continue through `More info` → `Run anyway` if you trust the release source.

### 📦 In-app updates

ShowRunner checks GitHub Releases for newer versions and uses Electron updater metadata when available.

| Platform | Supported assets |
|----------|------------------|
| Windows | `SAI.Showrunner-<version>-x64.exe`, `latest.yml`, `.blockmap`, `.zip` |

---

## 🛠 Troubleshooting

- **YouTube login is blocked** — Add your Google account as a tester in the OAuth consent screen while the app is in testing mode.
- **No active YouTube broadcast found** — Use manual Broadcast ID / Live Chat ID discovery in the YouTube integration page.
- **Moderation queue is empty** — Check that SAI Moderation Docker is running on port `8787` and that the integration is enabled.
- **OBS overlay does not update** — Verify the Browser Source URL is loaded in OBS and the overlay presence indicator is connected.
- **SmartScreen warning on Windows** — See [Windows note](#️-windows-note) above.

---

## 🤝 Contributing

PRs are welcome! Please:

- Keep commits small and conventional
- Preserve upstream ShowRunner license notices
- Run `corepack yarn check` before submitting TypeScript/Vue changes
- Use feature branches instead of committing directly to `main`

---

## 🙏 Credits

- Original upstream project: **LordTocs / [ShowRunner](https://github.com/LordTocs/ShowRunner)**
- ShowRunner is an AGPL-3.0 fork — not an independent reimplementation

---

## 📄 License

AGPL-3.0. See [LICENSE.md](LICENSE.md).
