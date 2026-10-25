# Changelog

## Unreleased

### Features
- Add macOS Intel/Apple Silicon installers and portable ZIPs, plus Linux x64 DEB installers and portable archives, with secure OS-keyring credentials, platform data directories and native window/browser lifecycles with awaited window setup and application-level Linux exit after runtime shutdown; preserve stored secrets when OS keys or key metadata are missing, and report Windows-only global input as unavailable without aborting desktop startup.
- Add shader graph node search with Ctrl+F and a snap-to-grid toggle using the shared immutable canvas controls.
- Keep overlay canvas/save actions usable in compact desktop layouts, with a keyboard-toggleable inspector/layers panel that retains draft and focus state across resizing.
- Add semantic overlay edit history with keyboard undo/redo/save, stable layer selection and one undo step per canvas gesture.

### Fixes
- Reject malformed Remote/Satellite identities, SDP and ICE before creating native peers or applying candidates; require typed share-list identities instead of coercing payload values into account IDs, project only rendered dashboard fields and bound/sanitize remote state subscriptions.
- Bound shader source, uniform and GPU surface resources, reject non-finite GPU inputs and release renderer resources once while ignoring queued frames after disposal.
- Remount the browser widget renderer when a saved widget changes type while retaining its ID, instead of updating the previous widget implementation with another type's fields.
- Scope audio cancellation by overlay and playback ID, cancel duration timers on abort/shutdown and report undelivered playback as failed instead of successful.
- Require overlay-scoped browser capabilities for config, media and WebSocket access, store the installation secret encrypted, bootstrap HttpOnly path-scoped cookies and restrict state/viewer projections to configured widget fields; existing OBS sources need the current Browser Source URL copied or fixed from the editor.
- Render leaderboard names and selected values in the browser's row format, reuse numeric-aware row ordering across providers and bound provider prefixes and paginated response size.
- Recheck shared-dashboard permissions and current button definitions before remote commands, close revoked sessions on refresh, bound pending remote RPCs and keep provider error text and stale callbacks out of disconnected sessions.
- Prevent stopped, timed-out or unregistered HTTP handlers and endpoint routes from continuing dispatch; serialize listener startup/shutdown so concurrent starts cannot leak a server.
- Ignore obsolete remote discovery failures and connection/RPC continuations after workspace replacement; keep provider, startup, registry and queue errors out of public diagnostic payloads.
- Keep chat moderation and command dialogs on their original runtime/manager, retain newer composer drafts after sends and prevent duplicate submissions or raw provider error displays.
- Keep profile trigger choices, activation and save completion scoped to the selected profile; retain newer edits during saves and keep profile/condition controls usable with enlarged text.
- Keep resource catalogs, open dialogs and Stream Plan actions tied to their original project; reject stale CRUD submissions and show safe retry feedback after failed operations.
- Keep plugin/settings loads and OAuth completion scoped to their form owner; reject malformed numeric settings, retain failed drafts and redact credential-bearing configuration previews and provider error payloads.
- Stop chat messages from rebuilding Twitch controls and triggering health reads; keep dashboard queue counters scoped to each named queue and observe live queue, plan and provider status at the corresponding card.
- Prevent delayed viewer-table queries from replacing newer sorting/project results, and refresh displayed variable values without rebuilding unrelated viewer controls.
- Retain shader palette search across panel toggles, reject picker results from a reset graph and show unsupported shader documents without raw exception payloads.
- Keep graph pickers, diagnostics, compact inspectors, parameter forms and run completion scoped to their document; prevent long subgraph names from overflowing the toolbar and hide provider error payloads in resource fields.
- Refresh edited style inputs after undo or external changes, keep open font editors on current values, and preserve removed/null optional effects instead of restoring them from defaults.
- Isolate open preview dialogs from document switches and preserve additional preview configuration fields during editing and saving.
- Keep OBS source dialogs and delayed responses scoped to the selected overlay/connection, preventing old dialogs from creating sources for a new document.
- Reject delayed overlay presence replies from previously selected documents instead of displaying another resource's connection status.
- Keep overlay inputs and save completion isolated when switching resources, preserve layer selection after deletion, keep open layer menus on their original layer after reordering and show save failures without exception payloads.
- Persist variable values without replacing concurrent authoring edits, unrelated state or deleted resources; serialize ID/alias updates and initialize defaults before reset.
- Preserve unbounded queue timeouts and unknown Stream Plan segment fields across restart/editing; reject malformed nested resource data before overwriting it.
- Preserve unrelated settings during OAuth refresh and save verified YouTube credentials/channel identity together; reject outdated login/account writes.
- Keep the project catalog cached across unrelated UI rebuilds, refresh it through an owned storage watcher and report unreadable directories without discarding healthy project entries.
- Keep unreadable resources visible with safe diagnostics instead of hiding them, and prevent malformed parser source from reaching resource errors/logs.
- Serialize viewer updates across repository owners, reject stale definition edits and report corrupt viewer data instead of silently skipping it; preserve provider-qualified identities and group membership.
- Keep resource form drafts open after failed saves and prevent duplicate submissions without exposing credential-bearing errors.
- Reject stale resource, automation, profile and queue editor saves/deletes and concurrent profile activation updates and duplicate creation instead of silently replacing another owner’s data; preserve newer in-flight edits when advancing the saved baseline.
- Reject dangling filesystem redirects and recursive YAML aliases, handle secret roots with trailing separators and clear native DPAPI buffers after use.
- Recover plugin settings and encrypted credentials together after interrupted saves, reject stale settings forms, serialize independent owners and keep unknown encrypted fields opaque to editors and public settings/resource files; publish dock registration and its token together.
- Recover resource config, runtime state and encrypted credentials as one generation after interrupted saves/deletes; serialize repository owners across processes and preserve externally changed files on recovery conflicts.
- Fail visibly when encrypted credentials are unavailable, reject declared secret writes without encrypted storage, and preserve unsupported or mismatched resource documents instead of overwriting them.

### Refactors
- Separate Remote/Satellite control-session ownership from signaling and WebRTC adapters; start bounded RPC deadlines before native sends, close stale channels and settle timers/writes on teardown without late state updates; serialize signaling startup/stop and release sockets/native peers that arrive after shutdown, bound host sessions/ICE queues and cancel owned file-watch timers, closing native peers before waiting for blocked offer creation.
- Generate shared render budgets for Dart/TypeScript and separate typed shader frame inputs from WebGL calls; preserve semantic-only GLSL invalidation and reject oversized authoring graphs without changing saved documents.
- Give overlay peer admission its own manager, with authenticated connection limits and awaited join/configuration/serving teardown behind the existing service facade.
- Coalesce overlay state snapshots with one in-flight update per connection, skip unchanged values, retain the latest queued values and drain pending state promises on disconnect without coalescing events or widget commands.
- Separate overlay HTTP resources, canonical media containment and audio ownership; project browser configuration from declared widget fields, omit shader authoring documents and bound render resource allocation.
- Separate chat dock listener ownership, immutable HTTP routing and typed command/snapshot contracts; validate payload shapes and platform limits before provider work, return safe error codes and serialize dock restart/shutdown.
- Use generated, versioned resource-scoped envelopes for Remote/Satellite control channels, reject recent request replay and bound active operations; serialize satellite disconnect cleanup and ignore messages after disposal.
- Separate overlay browser RPC dispatch, validate method arguments before repository/event access, cap viewer pages and state subscriptions, and reject widget calls targeting another overlay or a deleted widget.
- Generate one strict, versioned overlay WebSocket envelope for Dart and TypeScript, bind messages to their overlay resource and return payload-free RPC errors; reject unsupported wire formats and bound browser connection/send lifetimes.
- Give overlay WebSocket peers owned request timers, bounded pending/in-flight calls and replay protection; close expired peers, drain pending joins on shutdown, cap connections before loading resources and bound browser-side pending RPCs before allocating timers.
- Separate remote discovery transport from its workspace, cache plugin-health requests in an owned diagnostics panel and provide explicit health refresh without issuing reads during ordinary rendering.
- Separate the virtualized chat timeline and command editor form; isolate live message notifications from workspace filters/search while leaving history, actions, permissions and cooldowns in their existing runtime owners.
- Separate profile trigger selection and inline automation panels, guard asynchronous loading after close and remove an unused session/disposal path while retaining managed runtime ownership.
- Separate resource creation forms from catalog routing and capture repository, registry and runtime owners before asynchronous editor work.
- Separate integration metadata/search/usage from settings drafts and interface preferences, share typed setting fields and load one coherent settings baseline outside rendering without reading plugins that declare no settings.
- Give Twitch chat activity and channel refresh independent view owners, split dashboard cards and share reusable workspace notices without moving provider workers into widgets.
- Separate global variables, viewer queries and value forms; cache the variable catalog, coalesce refreshes and keep per-value notifications away from filesystem reads.
- Separate shader toolbar, palette, inspector, search and compile-result presentation; palette filtering no longer rebuilds the shader workspace or invalidates compiled output.
- Extract automation graph toolbar, node picker, inspector, parameter form and resource-field loading; refresh execution controls and node visuals without rebuilding the authoring workspace on trace updates.
- Split structured overlay inputs into focused font, text/alignment, geometry, outline, background and gradient controls with shared inspector sections, optional groups and schema field rendering.
- Give overlay preview settings an owned form with retained disabled values; reset inspector presentation on document identity changes and reject delayed inspector edits from old documents.
- Separate overlay OBS orchestration from toolbar rendering, with captured operation targets, debounced/coalesced inspection, owned writes and payload-free retry status.
- Own overlay presence polling separately and refresh only status/URL widgets, avoiding canvas rebuilds, overlapping polls and exception-bearing browser errors.
- Move overlay authoring, semantic dirty state, immutable snapshots and save ownership into an independently testable editor controller; give responsive layout, the inspector/layers splitter and layer list/actions separate presentation owners.
- Validate resource configurations through provider-owned codecs shared by storage and editors, with distinct unsupported-schema diagnostics and semantic JSON/YAML round-trip coverage for every resource family.
- Route application and provider storage through typed project factories anchored to the app directory, including public config, journals, locks and encrypted credentials; remove unused untyped resource writers and route project commands, chat/usage catalogs, provider automation loading and profile activation through the same owners.
- Share typed single-document storage across automation/profile/queue repositories, with explicit domain store contracts and validation under the same owner lock as atomic publication.
- Split resource editors into provider-owned Flutter libraries and contribution packs, with separate overlay toolbar/palette/rename controls and dashboard creation forms, shared inputs, explicit editing capabilities and safe read-only fallbacks that block unavailable plugin writes while retaining mounted document drafts/history.
- Catalog persisted document ownership, formats and required public/secret coherence boundaries from canonical resource declarations.

### Docs
- Document desktop package formats, native proof hosts, OS-keyring behavior, portable data locations, default SDK rendering and macOS/Linux support limits.
- Document overlay/Remote transport ownership, public projection limits, authentication and measured browser/native/visual proof boundaries.
- Document completed workspace view-state boundaries, editor/dialog ownership, responsive input contracts and measured Flutter/native/visual checks, including active-document identity and owned Save All completion, with explicit live-provider/device limitations.
- Document typed storage ownership, journal recovery and stale-write policy, provider editor/codec boundaries, secret handling and measured Phase 04 validation limits.

### CI & Build
- Build and smoke-test macOS/Linux installer and portable artifacts in isolated CI; publish releases only after every platform package passes, retain application logs and native launcher crash diagnostics, verify unlocked CI keyrings and wait for complete application startup and rasterized frames before running or closing scenarios, and cancel obsolete proof jobs independently per platform.
- Run a real Dart/Chromium authenticated overlay transport smoke in full local checks and Windows CI, alongside DOM/WebGL verification.
- Verify generated overlay and Remote/Satellite protocol codecs alongside widget contracts so runtime wire-schema drift fails CI; derive Dart formatter language from the package SDK constraint so clean checkouts and configured workspaces produce identical output.
- Verify workspace/dialog replacement, scoped chat and health rebuilds, layer-menu identity and desktop size/DPI behavior; await active document identity, accepted resource operations and sequential native Save All writes before checking persisted results.
- Add isolated persistence failure probes for mixed credential/config generations, hidden decryption failures, unsupported envelopes and resource identity confusion; await real filesystem completion in variable UI fixtures and ignore generated fixture owner locks; verify malformed resources survive native application restart without hiding healthy data or exposing parser source.

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
