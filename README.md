# ShowRunner

[![Build](https://github.com/saitatter/sai-showrunner/actions/workflows/build.yaml/badge.svg)](https://github.com/saitatter/sai-showrunner/actions/workflows/build.yaml)
[![Release](https://img.shields.io/github/v/release/saitatter/sai-showrunner?display_name=tag)](https://github.com/saitatter/sai-showrunner/releases)
[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](LICENSE.md)

ShowRunner is a desktop-first broadcaster production suite for Twitch, YouTube, OBS, overlays, stream automations, and external SAI services.

This project is an AGPL-3.0 fork of CastMate. Upstream architecture, plugin boundaries, and licensing are preserved while the app is being shaped into the SAI streaming toolchain.

## Current Features

- Twitch integration with profiles, channel point rewards, chat triggers, and stream automation.
- YouTube integration with browser OAuth, live chat ingest, chat command triggers, paid message triggers, membership triggers, and author flags.
- OBS WebSocket integration for scene/control actions.
- Overlay editing and OBS preview workflow inherited from upstream.
- Automation editor with both the original timeline view and a new node-based flow view.
- Node context inspector with right-click support, collapsible sections, and the same action/trigger configuration panel used by Timeline.
- Moderation Docker integration under `Integrations -> Moderation`, forwarding normalized YouTube chat messages to `POST /v1/chat-events`.
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

Release builds can bundle YouTube credentials with:

- repository variable: `SHOWRUNNER_YOUTUBE_CLIENT_ID`
- repository secret: `SHOWRUNNER_YOUTUBE_CLIENT_SECRET`

## Moderation Docker

ShowRunner can forward YouTube live chat messages to the SAI moderation docker.

Default URLs:

- API: `http://localhost:8787`
- Dashboard WebSocket: `ws://localhost:8787/ws?channel=dashboard`

In the app, open:

```text
Integrations -> Moderation -> Moderation Docker
```

Enable the integration, verify health, and leave `Forward YouTube chat` enabled. Approved overlay delivery is still owned by the moderation docker and overlay runtime.

## Automation Editor

Open or create an automation:

```text
Automations -> New/Open Automation
```

The editor starts in `Nodes` mode. Use:

- left click to select a node
- right click to open the node context inspector
- drag to organize nodes visually
- `Timeline` toggle for the legacy detailed editor

The node editor is currently a compatibility layer over the existing automation schema. Editing existing action and trigger config works through the inspector; full node-native add/connect/delete workflows are next.

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
