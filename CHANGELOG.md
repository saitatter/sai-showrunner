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
- Clarify Twitch Public OAuth setup and remove stale test-count claims from the node-testing guide.

### CI & Build
- Wait for asynchronous resource-list updates in native create/delete tests instead of relying on fixed frame delays.
- Handle Dart build-hook diagnostics in the local Windows PowerShell signing proof while preserving updater failure exit checks.
- Verify the production Debug executable before native integration tests replace its entrypoint, and check contract parity before expensive native builds.
- Pin the historical contract comparison to its immutable commit so clean CI checkouts do not require local-only tags.
- Scroll first-run setup controls into view during native tests on smaller Windows runner screens.
- Make releases manual from main with conventional-commit version selection, curated notes, dry-run and immutable-tag asset rebuilds.
- Keep Windows releases as drafts until signed packaging and updater smoke tests pass; signing proofs use the same protected release environment.
- Align the Flutter SDK and required CI checks with the supported development environment.
- Use current maintained workflow actions and cancel superseded CI runs without cancelling releases.
- Remove dependency-update rules for the retired semantic-release tooling.
- Pin the published graph packages and re-review inspector screenshot baselines for Flutter 3.47.7 without relaxing visual tolerances.

## Published history

Earlier releases and their notes remain available on [GitHub Releases](https://github.com/saitatter/sai-showrunner/releases).
The Unreleased section records the Flutter cutover relative to the last published stable tag; it is not a claim that this version has shipped.
