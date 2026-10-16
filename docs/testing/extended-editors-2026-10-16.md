# Extended application verification — 2026-10-16

## Scope and evidence

- Flutter regression: **735 passed, 7 opt-in live tests skipped**. Static analysis: no issues.
- Overlay renderer: **98 tests passed**, TypeScript checking passed.
- Shader catalog: **89 WebGL compilation/link/render checks passed**, covering previews for all 84 catalog nodes, four starters, and a numeric uniform-name regression. All starters produced nonblack images. These checks use the production renderer in headless Chrome with SwiftShader; they do not cover every input combination or GPU driver.
- Native Windows editor workflows: **45 cases passed**, covering shader presets, compilation, Apply/Cancel, palette, typed parameters and state bindings, clipboard, incompatible connections, frames, layout, deletion and undo/redo. Existing resource editor cases, Stream Plan transitions, dashboard host and local node fixtures run in the same native target. The additional opt-in native audio scenario also passed.
- Portable OBS on **4456**, verified against the workspace executable: compiled shader animation, live state-bound uniform changes, and state reacquisition after browser reconnection passed. The fixture restored the previous scene and removed its own test scene/source. Personal OBS was not used.
- Real Windows speech synthesis and MediaKit playback passed: generated WAV, trimming, TTS through a splitter, unavailable output handling, and cancellation. MP3/OGG/FLAC conversions are also played when ffmpeg is installed. Completion is checked programmatically; no claim of subjective listening quality.
- Dashboard host: button trigger through a compiled graph, invalid widget/name rejection, state subscribe/update/unsubscribe, channel closure and resubscription. Signaling and WebRTC channels are fixtures, not a live remote service.
- Remote Buttons: real local HTTP listing, missing-button rejection, concurrent presses through compiled graphs, stop/restart, and idempotent startup. Local HTTP, Discord and OBS transport fixtures remain covered by the local workflow suite.

## Repairs

- Generated shader identifiers could contain reserved consecutive underscores; 60 node previews failed actual WebGL compilation. Sanitization now handles preview IDs and numeric uniform-name fallbacks.
- Shader editor loading events could replace saved node IDs and break connections. Loading remains guarded until queued controller events finish.
- Shader deletion/undo could lose wires. Restored nodes recover their captured connections; redo remains available.
- Editing after compilation could apply a new graph with old GLSL. Changes invalidate the compilation result. Layout now uses the controller operation and supports undo.
- Invalid fragment compilation leaked WebGL resources. Shader/program allocation now cleans up on compilation failures.
- Concurrent Stream Plan navigation could execute the same transition twice. Operations reserve their queue position before waiting.
- Editing active Stream Plan components failed to stop removed components or activate additions. Updates now reconcile the old and new component sets.
- Routed TTS applied volume during synthesis and playback. File synthesis now uses full volume and the playback route applies the configured gain once.
- A native resource editor test needed explicit synthetic keyboard registration and focus settling; this was a test fixture correction.

## Repeat

From `packages/showrunner-flutter`:

```powershell
flutter test
flutter analyze
flutter test integration_test/resources/extended_editors_test.dart -d windows
$env:SHOWRUNNER_EXPORT_SHADER_FIXTURES = '1'
flutter test test/plugins/overlays/shader_graph_test.dart
Remove-Item Env:SHOWRUNNER_EXPORT_SHADER_FIXTURES
```

From the repository root, build and check actual WebGL output:

```powershell
node .yarn/releases/yarn-4.1.0.cjs overlay:build
node tools/overlay_registry/shader-catalog-smoke.mjs
```

Audio is opt-in because it uses the system output. From the Flutter package:

```powershell
$env:SHOWRUNNER_LOCAL_AUDIO = '1'
flutter test integration_test/resources/sound_live_local_test.dart -d windows
Remove-Item Env:SHOWRUNNER_LOCAL_AUDIO
```

For the OBS shader fixture, first start the workspace portable OBS with its existing test configuration on 4456. Set `SHOWRUNNER_SHADER_OBS=1` and `SHOWRUNNER_LIVE_CONFIG` to the absolute path of the ignored local YAML, then run `flutter test test/live/shader_obs_test.dart`. Clear the two environment variables afterwards. The test refuses another executable or port.

GPU reports are in `.tmp/shader-catalog/report.json`; OBS reports/screenshots are in the Flutter package's `.tmp/shader-obs-*` directories. These generated artifacts and credentials are not committed.

## Still requires external setup

This round does not establish live coverage for every integration. YouTube needs OAuth credentials and a live chat; Discord needs a test bot/server/channel; remote cloud dashboard needs a reachable service and authentication. Heart-rate BLE, Hue/Govee/Twinkly/Elgato/Kasa/LIFX/Wyze, VoiceMod, and server integrations need their respective test devices/services. Aitum/Advanced Scene Switcher need the corresponding portable OBS plugins. Paid/provider-specific TTS needs its configured provider.

Use `packages/showrunner-flutter/test/live/connections.local.yml` for secrets; its tracked example and `docs/testing/node-catalog.json` list settings and action schemas. Existing successful OBS/Twitch probes are documented in earlier reports; they are not proof that these other services work live. No credentials belong in chat or commits.
