# Product status and comparison boundaries

The maintained desktop is Flutter. Frozen contracts and screenshots refer to
commit `890ee2c9cc0522f2d8c747612920c6d12a1cb716`, not whichever implementation happens to be on
main after integration. The old desktop is not a supported runtime.

## Supported surfaces

| Surface | Current behavior | Remaining verification boundary |
| --- | --- | --- |
| Workspace | Resizable project sidebar, document tabs, dirty/save/close lifecycle | Native and narrow-layout tests; screenshots have their own acceptance rules |
| Automations | Immutable typed graphs, conditions, loops, subgraphs, variables, compiled execution and traces | Large-edit JIT timings can exceed a frame budget; no universal FPS guarantee |
| Profiles / Stream Plans | Trigger automations and serialized segment transitions | Real provider events require explicit live tests |
| OBS | Scene/source/media/filter/output control and browser overlays | Use portable OBS; streaming/recording and Studio Mode have real side effects |
| Twitch | OAuth, chat, moderation, rewards, polls/predictions and events | Eligibility, permissions and event delivery are separate checks |
| YouTube | Chat, membership and paid-message events with chat/moderation actions | Real channel/live-chat authorization is required |
| Overlays / shaders | Typed widgets, aligned canvas, actual WebGL shaders and state bindings | GPU/browser/OBS rendering must be tested separately from widget tests |
| Variables / queues | Persisted viewer data, session state, queue history, replay/pause/cancel | Fixtures verify behavior; persistence is not full configuration backup |
| Remote / Satellite | Host/client negotiation, button RPC, state subscriptions, label/button widgets | Real remote signaling/device connectivity is separate from local fixtures |
| Audio / devices | Local sound/TTS, BLE heart rate and supported lighting providers | Hardware, accounts and audio playback require opted-in tests |
| Updates | Release metadata, artifact validation, Windows install and rollback | Public releases still require a trusted signing certificate and signed proof |

Contract and product inventories live in [parity.json](parity.json) and
[product-surface.json](product-surface.json). They are checked from source; avoid
copying transient test/action counts into multiple documents.

## Deliberate exclusions

- No separate Timeline editor: graph authoring is the supported automation surface.
- No arbitrary third-party in-process plugin loader; ADR-003 describes the future
  isolated protocol direction.
- No persistent Media Library/catalog/scanner. Local file selection remains.
- No old-format document compatibility layer or silent rewrite/migration.
- No Electron/Vue desktop runtime. Frozen reference assets remain for verification.

## Open work

- Managed chat commands need proper filtering, aliases, cooldowns and permissions.
  The current chat-command starter has a statically identified filtering gap; see
  [the Streamer.bot comparison](streamerbot-comparison.md).
- Unified multi-platform chat, Kick, selected donation providers and broader Twitch
  lifecycle actions remain product gaps, not completed parity claims.
- Signed release publication requires configured release/signing credentials and a
  successful packaging/updater proof; PR checks alone cannot replace that proof.
- Frozen Electron screenshots have significant intentional/native-layout differences.
  The catalog reports those differences without claiming pixel parity. Selected
  Flutter regression regions have explicit tolerances. See [testing](testing.md).

Preserve the automation/overlay/shader authoring and Stream Plan workflows while
prioritizing missing streamer-facing features; action counts are not a parity score.
