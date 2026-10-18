# Testing

Use Flutter 3.47.7 / Dart 3.13.5, Node 22 and Yarn 4.1.0. Install the committed
lockfiles. Tests and smokes must use temporary application data; live settings,
OBS profiles and credentials are never disposable fixtures.

## Local checks and CI

```powershell
./scripts/ci-check.ps1
./scripts/ci-check.ps1 -Integration -Visual
```

The default runs documentation/version checks, overlay tests/typechecking, browser
boundary verification, generated-registry checks, Flutter formatting/analysis/tests,
and contract/product inventories. Integration adds the native Windows lifecycle
suite; Visual captures isolated 1440x900 fixtures and runs catalog/regression checks.
CI also builds Windows Debug/Release, tests signing helpers with isolated fixtures,
runs startup smokes, and exercises the production overlay in Chromium.

Required GitHub checks retain the branch-protection names test-windows,
scripts-ubuntu and release-dry-run. The release preview is read-only and does not
require publishing credentials. Manual Release reuses the same workflow on the
exact planned commit; nightly adds repeated benchmark sampling.

## Focused checks

```powershell
node .yarn/releases/yarn-4.1.0.cjs overlay:test
node .yarn/releases/yarn-4.1.0.cjs overlay:typecheck
node .yarn/releases/yarn-4.1.0.cjs overlay:build
node .yarn/releases/yarn-4.1.0.cjs overlay:browser-smoke
Push-Location packages/showrunner-flutter
flutter test
flutter analyze --fatal-infos
Pop-Location
```

The graph runtime has an interpreter oracle and compiled VM fixtures. Native tests
cover authoring, strict persistence, save/reopen, selection/focus, undo/clipboard,
profiles, queues, resources, remote/provider lifecycle and overlay/shader workflows.
Do not treat test counts from retired implementations as current coverage; use the
current CI result. The last completed graph-cutover verification recorded 650
unit/widget passes with 7 opt-in probes skipped, all 21 native integration files,
and 89 actual WebGL shader compile/link/render fixtures. This is historical evidence,
not a promise that current changes have already passed.

## Visual checks

See [the visual harness](../tools/visual_parity/README.md). The historical Electron
catalog is diagnostic; a green comparison does not establish pixel equivalence.
Selected Flutter baselines have explicit regions and a 0.5% differing-pixel limit
at channel threshold 3. Keep the threshold and frozen reference images intact.

### Reviewed baseline SDK transition

The reviewed baselines were originally committed in e64552bb1 when CI pinned
Flutter 3.44.0. The main-integration work pins all workflows to Flutter 3.47.7 /
Dart 3.13.5, matching the maintained local toolchain. Fresh isolated 1440x900
captures reproduce the prior label/font differences of 2.248024% / 0.885130%.
The pre-rewrite inspector had reproduced those same differences on this SDK;
this is not a newly introduced graph-editor layout change.

The two inspector crops were inspected side by side: text/font choices, alignment,
geometry, color inputs, stroke and shadow controls remain the intended UI. The
reviewed Flutter PNGs are refreshed for this supported SDK. No product widget,
frozen Electron image, comparison region, channel threshold or 0.5% tolerance is
changed. Repeat the independent capture/regression check after the refresh; its
actual result, and the CI artifact, determine whether the gate passes. Do not
assume that copying a capture alone proves determinism or cross-runner behavior.

## Browser shaders and audio

Export fixtures from the Flutter shader tests with SHOWRUNNER_EXPORT_SHADER_FIXTURES=1,
then run `node tools/overlay_registry/shader-catalog-smoke.mjs` after overlay:build.
The browser test compiles and renders real WebGL output; it does not cover every GPU.
Local native audio tests are opt-in with SHOWRUNNER_LOCAL_AUDIO=1 and can use system
output. Simulated services and successful WAV generation are not subjective audio
quality validation.

## Benchmarks

Nightly runs tool/graph_benchmark_test.dart and tool/graph_execution_benchmark_test.dart
five times and summarizes median/p95 values with tools/benchmarks/summarize.mjs.
They verify history/serialization, compiler caching, loops and subgraphs as well as
timings. JIT wall-clock results are not GPU frame rates. Large immutable edits can
exceed one frame; do not claim 60 FPS from these measurements.

## External services and release proof

Use [live-services.md](testing/live-services.md) and [live-nodes.md](testing/live-nodes.md)
for credentials, eligibility and previously demonstrated limits. Explicitly distinguish
fixtures, API acceptance and delivered real events. Never auto-enable write scenarios
or print tokens. The [release checklist](release-checklist.md) remains an
operator gate; signed installed upgrade/rollback needs real signing credentials.
