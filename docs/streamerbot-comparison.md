# Streamer.bot feature comparison

## Scope

Compared official Streamer.bot documentation with the current Flutter application
under `packages/showrunner-flutter/lib`. Legacy TypeScript plugins, marketing
claims and generic HTTP/PowerShell workarounds are not counted as native feature
parity. This is a source/documentation audit, not a new live-service test run.
No personal profiles, credentials, provider settings or running streams were changed.

The official changelog lists 1.0.7 as stable and 1.1.0 as alpha. The alpha advertises
an integrated Points Service, Whisper.net voice control, Cron, controller input
and additional Elgato support. These are tracked separately from stable features.
Documentation can include alpha additions, so this is a capability comparison,
not a claim of exact version-by-version or action-count parity.

## Already present

- Visual graph authoring and execution, conditions, reusable automations, variables,
  profile activation and Stream Plans.
- Named automation queues, pending/running/history, pause, cancellation and traces.
- Twitch actions/events, OBS control, YouTube chat/membership/paid-message events.
- Persisted per-viewer data and global variables; viewer groups.
- Sound and local TTS; keyboard shortcuts and simulated keyboard/mouse input.
- HTTP requests/endpoints, overlay WebSockets and remote/Satellite dashboard RPC.
- Overlay editing, chat/paid alerts, custom widgets and shader graph authoring.
- Discord webhook messages, DonorDrive, Voicemod and multiple lighting providers.

Presence in code does not imply every external integration was tested live.
Existing live-test limits are recorded in `docs/testing/`.

## Feature gaps

| Capability | Current ShowRunner evidence | Missing or partial | Priority |
| --- | --- | --- | --- |
| Managed chat commands | `features/automation/automation_starters.dart`; Twitch chat trigger | No dedicated cross-platform command manager with aliases, parsing modes, global/user cooldowns, permission enforcement and counters. Raw chat plus conditions is not equivalent. | P0/P1 |
| Unified chat client | Separate Twitch/YouTube workspaces; overlay chat actions | No unified Twitch/YouTube/Kick message history and composer, per-message/user quick actions, emote autocomplete or dedicated chat OBS dock identified. | P1 |
| Kick | No Flutter provider, OAuth/runtime, manifest or UI identified | Native chat, moderation, platform events and platform-state integration. | P1 if multistreaming |
| Donation/commerce integrations | DonorDrive exists; generic HTTP endpoints exist | No native StreamElements, Streamlabs, Ko-Fi, Fourthwall, Patreon, Throne, Shopify, StreamLoots or TipeeeStream integration identified. Generic endpoints require users to implement mappings/auth themselves. | P1 for selected providers |
| Twitch action breadth | `plugins/twitch/actions/stream.dart`, `actions.dart` | Poll/prediction creation exists; corresponding get/terminate/archive/lock/resolve/cancel actions are not exposed as dedicated native actions. Also missing documented pinned-message, channel-tag, VIP/moderator-management and warn-user actions. | P1 |
| MIDI | Input plugin exposes keyboard/mouse simulation and keyboard shortcut trigger | No MIDI device lifecycle, incoming Note/CC triggers or outgoing MIDI actions identified. | P2 |
| Voice commands | TTS exists in sound plugin | TTS is speech output, not speech recognition. No microphone recognition, phrase/confidence configuration or voice-command triggers identified. | P2 |
| Elgato ecosystem | Elgato manifest exposes light/device actions | No native Stream Deck integration/plugin, Wave Link or Camera Hub integration identified. Current Elgato support is not the complete ecosystem. | P1/P2 |
| Deck/dashboard controls | `plugins/dashboards/ui/dashboard_widget_config.dart` registers label and remote button; Satellite sends state updates | Remote dashboards already exist. Missing richer slider/toggle/chart controls and dedicated actions for modifying item title/icon/value/state/pages, compared with Decks. | P2 |
| Quotes and credits | Viewer data, events and overlay primitives exist | No dedicated quote store/management or built-in stream credits recorder identified. These could be assembled manually, but are not packaged features. | P2 |
| Reusable share packages | YAML/JSON persistence, resources and starter templates exist | No ready-to-share bundle workflow with dependent automations/triggers/queues/resources, conflict preview and import/export wizard identified. | P1 |
| Configuration backups | Updater has executable backup/rollback; data uses persistent files | No equivalent startup configuration snapshots and user-facing full data backup/restore workflow identified. Updater rollback is not a complete project-data backup. | P1 |
| Custom scripting/extensions | Graph expressions, PowerShell, process launching and typed built-in Dart plugins | No in-app C# code/API equivalent or external runtime plugin SDK. ADR-003 intentionally defers arbitrary in-process plugins; an isolated versioned protocol is the documented future direction. | P2 |
| Additional streaming/VTuber apps | OBS and Aitum/ADVSS integrations exist | No native Meld Studio, Streamlabs Desktop, PolyPop, VTube Studio, Crowd Control or T.I.T.S. integration identified. | P2/P3 by demand |
| Public automation API breadth | HTTP endpoints and remote/overlay protocols exist | Not missing networking as a whole. No equivalent general documented automation HTTP/WebSocket/UDP API and arbitrary client/server configuration surface identified. | P2 |
| Alpha-only services | Timers/repeat and persisted viewer variables exist | No dedicated points service, Cron scheduler, controller button/axis input or Whisper voice runtime identified. Compare with 1.1 alpha separately. | P2/P3 |

Priorities are product recommendations, not implementation estimates. P0 means
verify/fix correctness before adding more surface; P1 is the first product wave.

## Static correctness finding: chat-command starter

The `twitch-chat-command-reply` starter declares `config.command.match = !hello`
(and a `cooldown` placeholder), then connects the chat trigger directly to the
send-chat action. However:

1. `plugins/twitch/actions.dart`, `_twitchTrigger`, builds chat using
   `_emptyTwitchTrigger`.
2. `_emptyTwitchTrigger` uses `TwitchEmptyConfig` with no `matches` callback.
3. `plugins/registry/plugin_contract.dart`, `TriggerSpec.matchesRuntime`, returns
   true when no matcher is provided.
4. `runtime/profile_runtime.dart` dispatches matching trigger events to the graph;
   it does not implement a separate command/cooldown matcher.

Consequently, the declared command configuration is not enforced by this path.
The starter can reply to unrelated messages unless an explicit graph condition
filters them. This is a static finding, not a live-channel reproduction. Validate
with matching/nonmatching messages, aliases, role checks, per-user/global cooldowns
and bot-message exclusion before calling managed commands supported.

## Recommended sequence

1. Verify/fix command filtering and establish a shared command model/runtime.
2. Add a command workspace (aliases, arguments, permissions and cooldowns).
3. Add unified Twitch/YouTube chat, per-message actions, then Kick if wanted.
4. Add the highest-value donation providers and complete Twitch poll/prediction
   lifecycle actions.
5. Add shareable automation packages and full configuration backup/restore.
6. Expand remote dashboards and add Stream Deck, then MIDI/voice and niche apps.

Our strongest differentiated surface is integrated graph/overlay/shader authoring,
Stream Plans and production workflows. Keep this investment rather than treating
raw action-count matching as the product objective.

## Local evidence

- `packages/showrunner-flutter/lib/plugins/registry/configured_plugin_registrar.dart`
- `packages/showrunner-flutter/lib/plugins/twitch/actions.dart`
- `packages/showrunner-flutter/lib/plugins/twitch/actions/stream.dart`
- `packages/showrunner-flutter/lib/plugins/twitch/contracts.dart`
- `packages/showrunner-flutter/lib/plugins/registry/plugin_contract.dart`
- `packages/showrunner-flutter/lib/runtime/profile_runtime.dart`
- `packages/showrunner-flutter/lib/runtime/action_queue.dart`
- `packages/showrunner-flutter/lib/features/automation/automation_starters.dart`
- `packages/showrunner-flutter/lib/plugins/dashboards/ui/dashboard_widget_config.dart`
- `packages/showrunner-flutter/lib/plugins/remote/dashboard_host.dart`
- `packages/showrunner-flutter/lib/plugins/input/manifest.dart`
- `packages/showrunner-flutter/lib/services/update_install_service.dart`
- `packages/showrunner-flutter/lib/persistence/viewer_data_repository.dart`
- `docs/architecture/adr-003-external-plugins.md`
- `docs/testing/live-services.md`
- `docs/testing.md`

## Official sources checked

- [Core features](https://docs.streamer.bot/guide/core)
- [Commands](https://docs.streamer.bot/guide/core/commands)
- [Actions and queues](https://docs.streamer.bot/guide/core/actions)
- [Sub-actions catalog](https://docs.streamer.bot/api/sub-actions)
- [Integrations](https://docs.streamer.bot/guide/integrations)
- [Chat](https://docs.streamer.bot/guide/extra-features/chat)
- [Decks](https://streamer.bot/)
- [MIDI](https://docs.streamer.bot/guide/core/midi)
- [Voice control](https://docs.streamer.bot/guide/core/voice-control)
- [Import/export](https://docs.streamer.bot/guide/core/import-export)
- [Backup/restore](https://docs.streamer.bot/guide/core/backup)
- [Quotes](https://docs.streamer.bot/guide/core/quotes)
- [Credits](https://docs.streamer.bot/guide/core/credits)
- [API overview](https://docs.streamer.bot/api)
- [Release channels](https://streamer.bot/changelogs)
- [1.1 alpha features](https://docs.streamer.bot/changelogs/v1.1.0)
