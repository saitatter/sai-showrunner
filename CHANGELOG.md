# Changelog

## Unreleased

### Features
- Replace the desktop application with the Flutter production workspace, including typed immutable automation and shader graphs, overlays, profiles, queues and Stream Plans.
- Add integrated Twitch and YouTube workspaces, remote dashboards, viewer data, local audio and Bluetooth heart-rate workflows.

### Fixes
- Preserve graph history, clipboard dependencies and execution traces across editing, saving and reopening documents.
- Reject unsupported document formats without silently overwriting them.
- Restore overlay subscriptions and pending-call handling after browser reconnects.

### Refactors
- Remove the Electron/Vue desktop runtime while retaining the browser overlay required by OBS.

### Docs
- Consolidate historical audits into maintained architecture, testing, product-status and Streamer.bot comparison documents.
- Document contribution rules and isolated testing requirements in AGENTS.md.

### CI & Build

## Published history

Earlier releases and their notes remain available on [GitHub Releases](https://github.com/saitatter/sai-showrunner/releases).
The Unreleased section records the Flutter cutover relative to the last published stable tag; it is not a claim that this version has shipped.
