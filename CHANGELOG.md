# Changelog

## Unreleased

### Features
- Render rich chat emotes with Twitch fragments and 7TV/BTTV/FFZ catalogs, bounded caching, animation preferences and text fallback.
- Add configurable global/message/user/event chat automation actions and a public Twitch/YouTube event feed in chat and the dock.
- Add shared chat display preferences, user/text/role highlights and bounded ignore rules with explicit command-blocking controls.
- Add keyboard command and local-action menus, paused chat views and exact user filtering in chat and the OBS dock.
- Add advanced command permissions, bounded regex, private Twitch sources, graph management actions and external Twitch moderation synchronization.
- Add managed Twitch/YouTube chat commands with aliases, argument parsing, permissions, cooldowns, persisted counters and named automation queues.
- Add unified Twitch/YouTube chat with moderation, emote suggestions and an authenticated local OBS browser dock.

### Fixes
- Synchronize YouTube ban/tombstone events and keep late deleted messages suppressed without clearing unrelated users or channels.
- Preserve settings through temporary Windows file-sharing locks by retrying atomic replacement without removing the original.
- Keep command priority controls correct while filtering the command list.
- Preserve workspace navigation during startup restoration.
- Enforce configured Twitch chat-trigger filters.

### Refactors

### Docs
- Document chat setup and remaining Streamer.bot differences using static .NET evidence and an isolated runtime UI comparison.

### CI & Build
- Recover draft release assets using the protected publishing job's permissions.
- Pass named packaging parameters correctly when building Windows releases.
- Wait for shader field edits to settle before switching inputs in native workflow tests.

## 2.0.0 - 2026-10-19

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
- Align the product inventory and live-service verification boundaries with unsigned Windows packaging.
- Explain parallel Windows gates, single-build native fixtures and exact-commit CI reuse during release, with measured baseline timings.
- Document unsigned Windows distribution and the publishing credentials still required for manual releases.
- Consolidate historical audits into maintained architecture, testing, product-status and Streamer.bot comparison documents.
- Document contribution rules and isolated testing requirements in AGENTS.md.
- Clarify Twitch Public OAuth setup and remove stale test-count claims from the node-testing guide.

### CI & Build
- Wait for confirmed Twitch keepalive reconnection in tests, avoiding a fixed wall-clock race while verifying the timeout cause and deadline.
- Keep unsigned package proofs compatible with Windows PowerShell build-hook diagnostics while still failing on updater errors.
- Reuse successful CI only for the exact trusted main commit during release; run fresh validation whenever that proof is absent or incomplete.
- Compile native lifecycle tests once and capture their visual fixtures in the same run, preserving all existing scenarios and visual tolerances.
- Publish unsigned Windows packages without requiring signing credentials, while retaining application and updater proofs before publication.
- Wait for asynchronous resource-list updates in native create/delete tests instead of relying on fixed frame delays.
- Handle Dart build-hook diagnostics in the local Windows PowerShell signing proof while preserving updater failure exit checks.
- Verify the production Debug executable before native integration tests replace its entrypoint, and check contract parity before expensive native builds.
- Pin the historical contract comparison to its immutable commit so clean CI checkouts do not require local-only tags.
- Scroll first-run setup controls into view during native tests on smaller Windows runner screens.
- Make releases manual from main with conventional-commit version selection, curated notes, dry-run and immutable-tag asset rebuilds.
- Keep Windows releases as drafts until packaging and updater smoke tests pass; manual package proofs use the same protected release environment.
- Align the Flutter SDK and required CI checks with the supported development environment.
- Use current maintained workflow actions and cancel superseded CI runs without cancelling releases.
- Remove dependency-update rules for the retired semantic-release tooling.
- Pin the published graph packages and re-review inspector screenshot baselines for Flutter 3.47.7 without relaxing visual tolerances.

## Published history

Earlier releases and their notes remain available on [GitHub Releases](https://github.com/saitatter/sai-showrunner/releases).
The Unreleased section records development after the latest published version.
