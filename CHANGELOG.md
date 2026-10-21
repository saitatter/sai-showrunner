# Changelog

## Unreleased

### Features

### Fixes
- Preserve unrelated settings during OAuth refresh and save verified YouTube credentials/channel identity together; reject outdated login/account writes.
- Keep the project catalog cached across unrelated UI rebuilds, refresh it through an owned storage watcher and report unreadable directories without discarding healthy project entries.
- Keep unreadable resources visible with safe diagnostics instead of hiding them, and prevent malformed parser source from reaching resource errors/logs.
- Serialize viewer updates across repository owners, reject stale definition edits and report corrupt viewer data instead of silently skipping it; preserve provider-qualified identities and group membership.
- Keep resource form drafts open after failed saves and prevent duplicate submissions without exposing credential-bearing errors.
- Reject stale resource, automation, profile and queue editor saves/deletes and duplicate creation instead of silently replacing another owner’s data; preserve newer in-flight edits when advancing the saved baseline.
- Reject dangling filesystem redirects and recursive YAML aliases, handle secret roots with trailing separators and clear native DPAPI buffers after use.
- Recover plugin settings and encrypted credentials together after interrupted saves, reject stale settings forms, serialize independent owners and keep unknown encrypted fields out of public settings/resource files; publish dock registration and its token together.
- Recover resource config, runtime state and encrypted credentials as one generation after interrupted saves/deletes; serialize repository owners across processes and preserve externally changed files on recovery conflicts.
- Fail visibly when encrypted credentials are unavailable, reject declared secret writes without encrypted storage, and preserve unsupported or mismatched resource documents instead of overwriting them.

### Refactors
- Route application and provider storage through typed project factories anchored to the app directory, including public config, journals, locks and encrypted credentials; remove unused untyped resource writers.
- Share typed single-document storage across automation/profile/queue repositories, with explicit domain store contracts and validation under the same owner lock as atomic publication.
- Split resource editors into provider-owned Flutter libraries and contribution packs, with separate overlay toolbar/palette/rename controls and dashboard creation forms, shared inputs, explicit editing capabilities and safe read-only fallbacks.
- Catalog persisted document ownership, formats and required public/secret coherence boundaries from canonical resource declarations.

### Docs

### CI & Build
- Add isolated persistence failure probes for mixed credential/config generations, hidden decryption failures, unsupported envelopes and resource identity confusion; await real filesystem completion in variable UI fixtures and ignore generated fixture owner locks.

## 2.1.0 - 2026-10-21

### Features
- Bound trace event/node/edge retention with explicit truncation counters, coalesce paused observer notifications and refresh execution visuals once per frame with stable run selection.
- Add immutable Twitch/YouTube provider events with credential redaction, private/public feed separation and bounded delivery queues that report overload without silently dropping accepted events.
- Render rich chat emotes with Twitch fragments and 7TV/BTTV/FFZ catalogs, bounded caching, animation preferences and text fallback.
- Add configurable global/message/user/event chat automation actions and a public Twitch/YouTube event feed in chat and the dock.
- Add shared chat display preferences, user/text/role highlights and bounded ignore rules with explicit command-blocking controls.
- Add keyboard command and local-action menus, paused chat views and exact user filtering in chat and the OBS dock.
- Add advanced command permissions, bounded regex, private Twitch sources, graph management actions and external Twitch moderation synchronization.
- Add managed Twitch/YouTube chat commands with aliases, argument parsing, permissions, cooldowns, persisted counters and named automation queues.
- Add unified Twitch/YouTube chat with channel-scoped moderation, emote suggestions and an authenticated local OBS browser dock.

### Fixes
- Cancel active Stream Plan graphs at close, reject waiting transitions and clear failed provisional state while attempting all component cleanup and preserving cleanup failures.
- Keep credentials, private chat and sensitive viewer values out of trace previews; capture arbitrary result text only through an explicit trusted contract and retain error codes/types instead of raw exception text.
- Cancel and await profile-owned trigger work at session/host shutdown, prevent duplicate managed activation and retain background failures without unhandled futures.
- Keep timed-out queue actions owned until cleanup finishes, await standalone queue shutdown, cancel gap timers and allow retry after a temporary queue-load failure.
- Make concurrent queue drains share ownership before queue lookup, so waiting callers cannot report completion while an action is still running.
- Release owned audio playback, speech and Windows synthesis processes at module shutdown; propagate action cancellation before routed TTS playback.
- Start every cancellation abort callback before notifying synchronous waiters, preventing cleanup continuations from skipping physical shutdown.
- Prevent delayed Twitch/YouTube chat startup or broadcast discovery from reactivating disconnected sessions; release their owned requests on disconnect.
- Reject oversized TP-Link Kasa TCP frames from their headers instead of continuing to buffer their bodies.
- Stop reporting unconfigured or unverified provider connections as healthy; skip disabled health probes and bound their response deadline.
- Prevent overlapping YouTube chat polls and ignore late responses or errors after stopping the worker.
- Close the shared OBS action connection at host shutdown and prevent delayed requests from reopening it afterward.
- Disable graph run shortcuts when another workspace is active or the application runtime is unavailable.
- Close malformed or oversized overlay WebSocket peers safely and bound pending RPC calls and response deadlines.
- Reject forged HTTP authorities and foreign-origin remote-button requests before exposing data or dispatching actions.
- Preserve settings through temporary Windows file-sharing locks by retrying atomic replacement without removing the original.
- Preserve workspace navigation during startup restoration.
- Enforce configured Twitch chat-trigger filters.

### Refactors
- Memoize full semantic compiler signatures by immutable document identity in a bounded cache, retaining payload equality, entry-point invalidation and fresh runtime contexts; expose cache counters and repeatable timing/allocation probes.
- Isolate compiler labels/slots and pure VM value operations, preserving the 16-opcode format and validating program operand addresses before actions run.
- Separate trace models, events, snapshots, session production and retention behind the existing public trace facade without coupling them to Flutter or saved graphs.
- Separate typed queue source metadata from captured automation snapshots and isolate nested context collections so explicit replay uses the original graph and inputs.
- Route editor runs, inline tests, chat, graph actions, profiles and Stream Plans through typed graph invocations with immutable context snapshots, distinct queue receipts/results and classified failures; cancel inline tests when their editor closes.
- Share bounded provider I/O and retry policies while keeping protocol adapters separate; cancel owned requests at shutdown and finish token persistence already in progress.
- Own canonical resource declarations alongside each provider and derive the shared editor lookup from those same contracts.
- Separate Twitch EventSub sockets, subscription declarations and event parsing, plus YouTube event parsing, from worker lifecycle management while preserving event routing and payloads.
- Track plugin lifecycle separately from automation enable policy; serialize persisted toggles, start previously skipped modules once, preserve unused-registry teardown and roll back failed activation without disconnecting shared chat.
- Move first-party provider setup into owned, statically imported factories and separate Flutter UI assembly from transport composition without changing saved plugin contracts.
- Validate first-party plugin packs atomically, including dependency order, ownership, contract versions and canonical Flutter resource editor coverage before lifecycle startup.
- Compose application startup and workspaces through explicit owners, scoped capabilities and feature-owned registrations; isolate Stream Plan state per application.
- Retain asynchronous runtime and tray teardown, cancel background work, flush variable edits before registry shutdown and release reached plugin modules after partial startup failures.
- Give navigation, document sessions and execution workflows explicit owners with validated navigation persistence and guarded asynchronous saves; native fixtures await flush and shutdown before restart or storage cleanup.

### Docs
- Document graph invocation/queue ownership, profile and plan shutdown, trace privacy/retention, compiler/cache boundaries and measured Phase 03 validation limits.
- Document first-party provider composition, lifecycle/enable semantics, cancellation, bounded event delivery and the corresponding validation boundaries.
- Document application ownership and shutdown contracts, network trust boundaries and remaining baseline security work with measured validation evidence.
- Clarify that corrections made while implementing new features remain in their feature entries rather than release fixes.
- Document chat setup and remaining Streamer.bot differences using static .NET evidence and an isolated runtime UI comparison.

### CI & Build
- Keep the packaged updater smoke independent of release version bumps and run it in the Windows build gate before publication.
- Restore unpublished release notes and preparation metadata so failed draft attempts do not consume public release versions.
- Verify the About screen against the declared package version so release version bumps preserve the UI test contract.
- Run Windows packaging after successful release preparation when exact-commit CI reuse skips fresh validation; keep failed preparation and dry runs blocked.
- Validate corrupted graph contracts, unsupported versions and bounded control cycles; compare compiled and interpreted execution across 30 deterministic graph seeds, including nested calls, branches, three loop types, intermediate action state, cancellation and failures with reproducible synthetic graph dumps.
- Launch browser smokes through a responsive CDP endpoint, retain startup diagnostics and try another installed Chromium browser when startup fails.
- Add a reproducible cross-runtime source/import inventory and baseline behavior contract matrix.
- Wait for asynchronous command dispatch and Save All writes to complete before checking persisted lifecycle results.
- Speed up visual catalog comparisons by avoiding per-pixel allocations while preserving reports, diff images and strict thresholds.
- Scroll lazy sidebar groups into view before opening resources in the native visual catalog fixture.
- Add opt-in public 7TV/BTTV/FFZ catalog contract probes without credentials or account writes.
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
