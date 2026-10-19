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
Together, Integration and Visual capture during the same native run. The grouped
native entrypoint compiles once for all 22 fixture files; the fixture-inventory
test prevents new native scenarios being omitted. Individual files can still be
run directly, and the standalone capture command uses a smaller grouped entrypoint.
CI also builds Windows Debug/Release, tests signing helpers with isolated fixtures,
runs startup smokes, and exercises the production overlay in Chromium.

GitHub runs windows-build (production Debug/Release, startup and signing-helper
proofs) alongside windows-integration (analysis/unit tests, contracts, one native
suite, captured visual comparisons and Chromium). The required test-windows check
is an aggregate that runs even after a dependency failure and accepts only success
from both Windows jobs. The other required names remain scripts-ubuntu and
release-dry-run. No fixture, assertion, screenshot region or tolerance is dropped.

The previous sequential Windows job took 30m20s: native fixtures 13m, production
builds 5m38s, Flutter checks 3m07s, duplicate captures 1m38s and cold SDK-cache saving
2m32s. The grouped local native run passed 96 tests with one audio probe skipped
in 3m17s after a single 14s incremental compilation, with zero differing pixels in
both reviewed regions. Local timings are not a prediction for a hosted runner;
use GitHub job durations to judge CI improvement and distinguish warm/cold caches.

The release preview is read-only and does not require publishing credentials.
Manual Release reuses successful main-push CI only for the exact planned commit
with every gate completed successfully; otherwise it runs the reusable workflow.
Nightly adds repeated benchmark sampling. PRs target main,
and CI push checks run only on main to avoid duplicate migration-branch runs.

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
The first-run shell test uses a 1024x640 viewport and scrolls provider controls
into view before asserting hit-testability and clicking. Keep this smaller-screen
coverage so hosted runners exercise the same scrollable setup as desktop users.
Do not treat test counts from retired implementations as current coverage; use the
current CI result. The last completed graph-cutover verification recorded 650
unit/widget passes with 7 opt-in probes skipped, all 21 native integration files,
and 89 actual WebGL shader compile/link/render fixtures. This is historical evidence,
not a promise that current changes have already passed.

## Visual checks

Chat/Commands adds the native `application/chat_workspaces_test.dart` fixture:
create/edit/enable/delete, alias-to-queue execution, counters, shared provider
history, filters and reply selection. Its review captures use Flutter 3.47.7 /
Dart 3.13.5, 1440x900 at DPR 1, under
`packages/showrunner-flutter/.tmp/chat-ui/`. The added sidebar destinations and
new workspaces are intentional; captures were visually inspected. Frozen Electron
references and existing Flutter regression baselines are unchanged.
The full chat validation passed `ci-check.ps1 -Integration -Visual`; both reviewed
Flutter inspector regions had zero differing pixels. A native shader workflow
initially lost a binding after rapid field changes; the fixture now settles each
edit and checks its document value before continuing. Both occurrences in the
grouped Windows suite passed with the final binding assertions intact.

Advanced command fixtures additionally cover Allow/Deny users/roles/groups,
fail-closed group lookup, named regex captures and a pathological expression that
times out while the UI heartbeat keeps running. Graph plugin fixtures exercise
filtered lifecycle triggers, enable/delete and independent counter/cooldown resets.
The targeted Windows Chat/Commands fixture passes with the expanded editor; its
captured command list was inspected. Twitch delete/clear events are tested with
channel scoping and whisper input is asserted absent from public history. These
are fixture proofs; live whisper scopes and privileges remain unverified.

Preferences fixtures verify strict version/limit validation, platform-scoped
ignore/highlight identities, bounded regex rules, hide-only versus command-block
behavior, authenticated dock updates and preservation of unsupported preferences.
The native fixture edits display/highlight settings; Chromium verifies font and
history-direction synchronization. Captures were inspected, including highlight
text contrast. The capture contract remains Windows, Flutter 3.47.7, 1440?900/DPR 1;
no frozen inspector/Electron references or comparison thresholds were changed.

Configured chat-action fixtures cover immutable definitions, scoped targets,
platform enforcement, expired/deleted targets and curated public event fields.
The service composition fixture runs a user shortcut through the real saved-graph
queue and verifies resolved viewer/message/argument values. The native fixture
creates and executes a global shortcut and displays a public follow event;
Chromium verifies global/message/event requests and escaped event text.

The Chromium overlay smoke proof also exercises the chat dock with isolated mock
HTTP APIs: two-provider history, text escaping, filters, routing, emoji and reply.
These fixtures make no live provider calls and do not verify OBS/CEF itself.

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
changed. A second independent native capture passed with 0 differing pixels in both
regions at the unchanged channel threshold 3 and 0.5% limit. GitHub Windows
captures independently passed with 0 differing pixels in both regions. The full
21-file native suite also passed locally and on GitHub, with its opt-in audio
probe skipped. These results cover the pinned capture contract and SDK, rather
than establishing universal pixel equivalence across machines.

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
operator gate. Public packages and the manual Windows release proof are unsigned;
packaging still exercises installed upgrade/rollback without a signature requirement.
The separate signing-helper fixture uses a temporary test certificate only.
