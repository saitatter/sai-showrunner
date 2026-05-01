# ShowRunner

[![Build](https://github.com/saitatter/sai-showrunner/actions/workflows/ci.yml/badge.svg)](https://github.com/saitatter/sai-showrunner/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/saitatter/sai-showrunner?display_name=tag)](https://github.com/saitatter/sai-showrunner/releases)
[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE.md)

ShowRunner is a desktop-first broadcaster production suite for Twitch, YouTube, OBS, overlays, stream automations, and external SAI services.

This project is an AGPL-3.0 fork of CastMate. Upstream architecture, plugin boundaries, and licensing are preserved while the app is being shaped into the SAI streaming toolchain.

## Current Features

- Twitch integration with profiles, channel point rewards, chat triggers, and stream automation.
- YouTube integration with browser OAuth, live chat ingest, chat command triggers, paid message triggers, membership triggers, and author flags.
- OBS WebSocket integration for scene/control actions.
- Overlay editing with OBS preview workflow, visible browser-source URLs, and one-click URL copy.
- Automation editor with both the original timeline view and a new node-based flow view.
- Node context workflow with right-click command menus, collapsible trigger/action groups, action insertion, duplicate/delete/reorder controls, and the same action/trigger configuration panel used by Timeline.
- Moderation Docker integration under `Integrations -> Moderation`, with native queue/status UI, manual override actions, and a `Filter Chat Message` automation action.
- Native overlay widgets for targeted approved chat feeds and WebGL shader layers with bundled presets or locally edited fragment shader source.
- Semantic release workflow for packaged Windows builds.

## Local Development

Install dependencies:

```powershell
corepack yarn install
```

Run the desktop app in dev mode:

```powershell
corepack yarn dev
```

Build all Vite targets:

```powershell
node .\vite-util\multi-vite.mjs build
```

Build a local Windows installer:

```powershell
$env:CSC_IDENTITY_AUTO_DISCOVERY = "false"
corepack yarn build
```

## Clean YouTube Test Run

Use this when you want a clean local app data folder and explicit YouTube OAuth credentials:

```powershell
corepack yarn dev:clean:youtube -- -YouTubeClientId "your-client-id.apps.googleusercontent.com" -YouTubeClientSecret "your-client-secret"
```

## First Run Setup

Recommended local setup order:

1. Open `Integrations -> Twitch -> Account Login` and connect both Channel and Bot accounts.
2. Open `Integrations -> YouTube -> Live Integration`, confirm the OAuth checklist, then connect YouTube.
3. Open `Integrations -> Moderation -> Moderation Docker`, choose `Localhost`, save, run Health, then Send Test Event.
4. Create or open an overlay, copy the Browser Source URL, and add it to OBS.
5. Add a `Chat Feed` widget or `Shader Layer` widget in Overlay Studio when needed.
6. Create an automation and use `Nodes` mode for the graph workflow or `Timeline` for the upstream detailed editor.

Release builds can bundle YouTube credentials with:

- repository variable: `SHOWRUNNER_YOUTUBE_CLIENT_ID`
- repository secret: `SHOWRUNNER_YOUTUBE_CLIENT_SECRET`

## Moderation Docker

ShowRunner can use SAI Moderation Docker as a backend-only moderation service. The old docker-hosted `/dashboard` page remains available for compatibility, but the primary queue UI is now native in ShowRunner.

Default URLs:

- API: `http://localhost:8787`
- Dashboard WebSocket: `ws://localhost:8787/ws?channel=dashboard`

In the app, open:

```text
Integrations -> Moderation -> Moderation Docker
```

Enable the integration, verify health, send a test event, and leave `Forward YouTube chat` enabled. Approved overlay delivery is still owned by the moderation docker and overlay runtime.

Recommended automation flow:

```text
Twitch/YouTube chat trigger
-> Moderation: Filter Chat Message
-> condition on approved/verdict
-> Overlays: Push Chat Message
-> Chat Feed widget
```

`Filter Chat Message` sends `deliveryMode: "decisionOnly"` to `POST /v1/chat-events`, so moderation updates the queue and returns a verdict without publishing directly to an overlay. This makes ShowRunner the place where you decide which approved messages reach which overlay widget.

## Native Chat And Shader Overlays

Overlay Studio includes:

- `Chat Feed`: a configurable chat widget for approved Twitch/YouTube messages, with platform colors, font sizing, background opacity, fade time, max messages, layout, badges, and targeted widget delivery from automations.
- `Shader Layer`: a WebGL widget with bundled shader presets, a local custom fragment shader editor mode, color/intensity/speed controls, opacity/blend mode, and a fallback state if WebGL or shader compilation fails.

The older standalone `sai-chat-overlay` flow can be retired once your ShowRunner overlay contains a `Chat Feed` widget and automations push approved messages with `Overlays -> Push Chat Message`.

## Automation Editor

Open or create an automation:

```text
Automations -> New/Open Automation
```

The editor starts in `Nodes` mode. Use:

- left click to select a node
- right click to open the Windows-style command menu for triggers and actions
- drag to organize nodes visually
- `Timeline` toggle for the legacy detailed editor

The node editor is currently a compatibility layer over the existing automation schema. Editing action and trigger config works through the inspector, and common node-native operations are available from `Node Actions`.

Node editor controls:

- drag actions from the palette onto the canvas
- drop actions on an edge to insert them between nodes
- middle mouse drag pans the canvas
- `Ctrl + wheel` zooms
- `F` fits the graph
- `Ctrl + D` duplicates the selected node
- `Delete` removes the selected node

## Release

Main is protected by a repository ruleset. Work should happen on feature branches and land through PRs.

Release notes are generated from conventional commits. Prefer small commits with semantic scopes, for example:

```text
feat(youtube): add paid message trigger
fix(moderation): harden dashboard websocket reconnect
chore(branding): replace visible upstream references
```

## Upstream

ShowRunner is based on CastMate by LordTocs:

https://github.com/LordTocs/CastMate

Keep upstream license notices intact when moving or reusing code.
