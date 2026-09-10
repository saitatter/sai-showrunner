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
