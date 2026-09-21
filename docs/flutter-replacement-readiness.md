# Flutter replacement readiness

This checklist describes what is verified on `migration/flutter` before the
Flutter desktop build is used as the ShowRunner replacement candidate.

## Verified

- Flutter is the desktop implementation; the OBS browser source remains the
  browser-only HTML/WebGL surface required by OBS.
- The persistent Media Library and its migration-only catalog/scanner scope are
  removed. Local file picking remains available where Sound and overlay
  resources need it.
- `sai_nodes` owns the generic editor operations used by ShowRunner, including
  spatial selection, coordinate transforms, content revisions, atomic layout,
  graph splicing, and frames.
- Production graph execution uses the same flat-program model as `main`:
  `GraphExecutionEngine` → cached 16-opcode program → Dart VM. The interpreter
  remains an explicit parity oracle, with fixtures for control flow, data
  wires, mappings, subgraphs, cancellation, failures, and guards.
- ShowRunner keeps the product-specific graph schema, plugin contracts,
  runtime, persistence, shader graph, and overlay resource semantics.
- Overlay packages use the generated registry and strict TypeScript checks;
  Vue/Pinia is not part of the browser runtime.
- Overlay backend RPCs have a bounded lifecycle: every request has a timeout,
  pending calls are rejected on transport reset and runtime stop, and late
  responses from an older connection generation are ignored. The lifecycle
  suite covers viewer-data queries, widget RPCs, timeout, reconnect, and stop.
- Full-screen visual coverage includes deterministic empty-app and loaded-graph
  fixtures at 1440x900 with a 1x device scale.
- The graph benchmark covers 100, 500, 1,000, and 5,000 synthetic nodes and
  records load, selection, drag, layout, serialization, and undo/redo timings.
- The runtime benchmark records cold compile, cached lookup, execution, loop,
  and nested-subgraph timings for the production graph engine.
- Windows Release smoke covers first run, automation, workflow, profile,
  integrations, overlays, and update-state handling.
- The Windows CI signing proof signs every executable and DLL in a temporary
  bundle, then verifies updater install and rollback with signature checks after
  both replacement and restoration.

## Integration coverage

The Flutter integration gate runs the full pre-cutover workflow suite, not only
the original three smoke files. It covers:

- graph edit → dirty → save → close → reopen;
- Save All and Save / Discard / Cancel close decisions;
- compiled graph execution, nested subgraphs, queue execution, and profile
  triggers;
- plugin disable/re-enable, provider failure handling, and Twitch reconnect;
- repeated Twitch provider reconnect cycles to catch lifecycle leaks;
- authenticated Remote dashboard discovery through a local API boundary;
- Heart Rate plugin lifecycle, simulation action, published state, threshold
  trigger, and disconnect handling;
- resource create/read/update/delete, including the Resources UI Overlay
  create/edit/delete flow;
- strict schema failure handling without modifying an existing document.
- deterministic 1440x900 captures for the shell, Settings, Updates,
  Integrations, and graph workspace catalog.

Unsupported document shapes are rejected by design: the Flutter product has a
single strict V2 persistence contract. The schema integration test verifies
that this failure is isolated and that canonical V2 data remains intact after
a fresh repository reopen.

The updater remains `partial` in `docs/product-surface.json` until a
signed installed Windows upgrade and rollback are demonstrated. The updater
now keeps a versioned rollback backup in the user data directory, removes
stale files during replacement, restores automatically if installation or
restart fails, and exposes an explicit rollback operation. The remaining
gap is release-environment proof with a signed installed build.

## Current visual evidence

The frozen `main` captures and the Flutter catalog are checked in under
`test/reference/`. Both catalogs now cover the empty dashboard, Settings,
Updates, Integrations, Queues, Variables, Viewer Variables, and a complex
automation editor at the same 1440x900 capture size. Flutter also captures
Diagnostics, Logs, and About; the frozen Electron build does not expose its
Tools group. The main reference can be regenerated with
`corepack yarn visual:main` and the Flutter catalog with
`corepack yarn visual:flutter` when the local frozen Electron build is
available. Once both catalogs exist, `corepack yarn visual:compare:catalog`
generates one report and diff image per screen under `.tmp/visual/catalog`.
It reports differences by default without hiding them behind a binary pass;
use `--fail-above=<percent>` when a screen-specific gate is intentionally
ready to be enforced.

The controlled empty-app comparison is intentionally still red: the clean
reference exposes the frozen dashboard surface (including its Media shortcut),
while Flutter exposes the replacement provider cards, create controls, and the
intentional removal of the persistent Media Library. The latest comparison
measured 72.61% differing pixels. The other controlled pairs currently measure
53.48% for Settings, 73.59% for Updates, 78.84% for Integrations, and 68.49%
for the loaded graph. These numbers are evidence and a work queue, not a claim
of pixel parity. The graph pair now uses the same `Super Chat -> Add to Queue`
starter shape as the frozen reference, including the automation-flow title,
selected action, inspector, and clipped graph surface. The Integrations pair is captured with the same Updates workspace
active and the Integrations group expanded; the capture generator enforces
that order so it does not compare unrelated screens.

## Required checks

```powershell
corepack yarn install --immutable
corepack yarn overlay:test
corepack yarn vitest run libs/showrunner-overlay-widget-loader/src/runtime/overlay_runtime.test.ts
corepack yarn overlay:forbid-vue
corepack yarn overlay:build
corepack yarn parity:check
corepack yarn parity:product
corepack yarn test:flutter-integration

Push-Location packages/showrunner-flutter
flutter analyze
flutter test
flutter test test/runtime/graph_execution_engine_test.dart
flutter test tool/graph_benchmark_test.dart --reporter expanded
flutter test tool/graph_execution_benchmark_test.dart --reporter expanded
flutter build windows --release
dart run tool/update_smoke.dart --bundle=build/windows/x64/runner/Release
# For a protected release bundle, also pass --require-signature.
Pop-Location

.\scripts\smoke-flutter-windows.ps1 -Configuration Release
```

## Remaining release proof

These are environment-dependent release checks, not missing product
contracts:

- upgrade and rollback from a signed installed Windows build;
- pixel/image comparison of the full reference screenshot catalog;
- long-running Remote/Satellite and plugin lifecycle soak tests;
- live OBS rendering comparison for browser overlays and compiled shaders.

Until those checks are captured in their target environments, the Flutter
branch is a replacement candidate with explicit release proof still pending,
not a claim of complete production cutover.

The unsigned local bundle path is covered separately by
`tool/update_smoke.dart`: it executes the real installer script against a
temporary Windows bundle, verifies replacement and rollback contents, and
cleans up the launched test process. CI also exercises the same path with a
self-signed copy of every executable and DLL, including signature checks after
upgrade and rollback. Neither local proof replaces the trusted signed
installed release check.

When the protected Windows signing secrets are available, a release-proof
bundle can be produced with:

```powershell
$env:SHOWRUNNER_WINDOWS_SIGNING_CERTIFICATE_BASE64 = '<base64-pfx>'
$env:SHOWRUNNER_WINDOWS_SIGNING_CERTIFICATE_PASSWORD = '<pfx-password>'
.\scripts\package-flutter-windows.ps1 -Version <version> -SignWindowsBundle -RequireWindowsSignature
```

The signing helper removes the temporary PFX after signing and verifies that
every executable and DLL in the bundle has an Authenticode signature. No
certificate or password is stored in the repository.

The release workflow requires both
`SHOWRUNNER_WINDOWS_SIGNING_CERTIFICATE_BASE64` and
`SHOWRUNNER_WINDOWS_SIGNING_CERTIFICATE_PASSWORD` as protected secrets. It
refuses to publish an unsigned Windows archive. The update smoke test then
verifies signatures before installation, after upgrade, and after rollback.
