# Graph rewrite verification — 2026-10-18

The requested greenfield plan is preserved in the sibling sai_nodes repository at
docs/greenfield-plan.md. Library work is on rewrite/graph-1.0; application work is
on migration/flutter. All commits are local. No package or branch was published.

## Completed architecture

Phases A–G provide a pure Dart immutable graph core, strict version-1 persistence,
declarative definitions and semantic types, dependency-tracked resolution,
transactional commands, bounded history, clipboard, spatial indexes, shared scene
geometry, a virtualized Flutter canvas and scoped execution visualization.
Library docs/architecture.md, docs/api.md and docs/performance.md explain ownership,
integration and measured limits.

Phases H–K replace Showrunner authoring with one AutomationDocument and one
GraphController across root and subgraph spaces. Settings and stable signatures
participate in the same undo history. Plugin definitions expose all declared
fields and typed ports. The palette, asynchronous resource inspector, search,
subgraph navigation, diagnostics and narrow layouts use this model directly.
Tabs retain selection, camera and history. Saving marks the captured revision,
preserving edits made while a write is pending.

The VM and interpreter consume ephemeral projections with actual entity IDs;
definitions contain no runtime callbacks. Queues, profiles, stream plans and
inline editors use canonical documents. Run-from-node propagates the selected
space and parameter defaults. Traces support live, retained, pinned and concurrent
runs without dirtying authoring. Inline traces isolate canonical document IDs.
Clipboard carries transitive subgraph dependencies, remaps semantic references
while preserving literal JSON, and commits the entire paste in one undo step.
Pending clipboard reads cannot cross controller/space changes.

Phase L moves all 84 shader definitions, typed ports, compiler inputs, settings,
uniforms and bindings onto the same immutable core and canvas. Semantic revisions
invalidate GLSL; presentation edits reuse compilation. Node previews derive
separate documents. All starters leave room between resolved node bounds.

Phase M deletes the old application editor/runtime/schema, mutable library API,
event bus, prototypes, embedded runner, adapters and their superseded tests.
There are no old-format decoders, aliases or migration helpers. Unknown semantic
entities inside the new format remain available for diagnostics. Unsupported
stream-plan documents show a load error, disable activation/save and cannot be
silently overwritten. Static test fixtures use the new format directly.

## Current verification

- Application: 650 unit/widget tests passed; 7 opt-in external live probes skipped.
- Dart analysis passed with fatal infos; formatting passed across lib/test/tool/
  integration_test (542 files).
- All 21 local Windows integration files passed. Coverage includes document
  creation/edit/save/reopen, strict persistence, editor shortcuts and narrow
  layouts, inline execution, shader editing, overlay rendering/alignment, queues,
  resources, local audio, runtime, remote dashboard and provider lifecycles.
  The first catalog attempt exposed an old fixture; it passed after replacement.
- Library: 36 core tests; independent Dart-only resolution/analysis/tests passed;
  17 canvas/scene tests passed and one optional benchmark was skipped in that
  suite; those 17 interactions also passed on native Windows.
- Both library package publish dry-runs passed with zero warnings. Nothing was
  uploaded. Historical larger test counts included deleted implementations and
  are not current rewrite coverage.
- All 89 production WebGL shader fixtures compiled/linked and rendered without
  GL errors. Compiler/controller/UI tests additionally cover invalid drafts,
  malformed documents, clipboard, undo, starter switching, output reconciliation,
  bindings and parameter editing.
- Contract parity passed (26 improved, 6 equivalent); product-surface parity
  passed (16 workspaces, 518 Dart files). The visual catalog comparison passed.
- Windows Debug and Release builds passed. Standalone startup passed for both;
  Release first-run, automation, workflow, profile, integrations, overlays and
  updates smoke scenarios passed with isolated temporary application data.

The strict overlay screenshot gate remains red against the existing reviewed
baselines: label region 2.248024%, font region 0.885130% (limit 0.5%). An isolated
checkout of pre-rewrite commit e64552bb1, rendered on the same machine/SDK,
reproduced exactly those results. Comparing its two inspector regions directly
with the final application gives zero different pixels at channel threshold 3.
This is a pre-existing baseline mismatch, not an observed rewrite regression.
The baseline images and thresholds were not changed. Local SDK: Flutter 3.47.7 /
Dart 3.13.5; CI currently pins Flutter 3.44.0. The cause of the historical mismatch
is not established by this comparison.

Core and Flutter benchmarks ran five samples at 100/500/1000/3000/5000 nodes.
Host authoring benchmarks verify history and serialization at the same sizes;
runtime benchmarks cover linear 100/500/1000-node programs, a 100-iteration loop
and eight subgraphs, including compiler cache reuse. At 5000 nodes the host
checkpoint measured load 105 ms, move 171 ms and round-trip 83 ms; a 1000-node VM
run took 56 ms. These are local JIT wall-clock observations, not frame-rate
guarantees. Large immutable edits still exceed a frame budget; library performance
documentation records median/p95 measurements and this limit.

Logs, benchmark JSON and captures are ignored local artifacts. Application logs
are under packages/showrunner-flutter/.tmp; library evidence is under sai_nodes/
.tmp. Final application captures are under .tmp/visual/greenfield-final.

## Reproduction and external requirements

Application checks run from packages/showrunner-flutter: flutter test, dart analyze
--fatal-infos, and dart format --output=none --set-exit-if-changed lib test tool
integration_test. scripts/test-flutter-integration.ps1 lists the Windows gate;
shader workflows and local audio are included. The two tool/graph*_benchmark_test
files produce ignored authoring/runtime timing reports.

Git dependencies pin sai_nodes and sai_nodes_core to
efd339ddd0e976076b7476f34804c3a7834247c6. Local path overrides are ignored; tracked
pubspec.lock entries remain portable Git references. A clean remote checkout/CI
requires pushing that library history before the application branch. This has
not been done automatically.

The seven skipped probes need explicitly enabled live services/events; local
regression does not claim new Twitch moderation or OBS broadcast operations.
Existing credentials remain in ignored connections.local.yml. Personal OBS is
not used or modified; any OBS work must use the existing portable instance.
