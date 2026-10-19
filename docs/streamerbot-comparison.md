# Streamer.bot feature comparison

## Scope

Compared official Streamer.bot documentation with the current Flutter application
under `packages/showrunner-flutter/lib`. Legacy TypeScript plugins, marketing
claims and generic HTTP/PowerShell workarounds are not counted as native feature
parity. This combines source review, official documentation, static inspection of
the shipped Streamer.bot 1.0.7 artifacts and an authorized isolated UI inspection.
It is not a live-service test run.
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
| Managed chat commands | Development: Chat Commands workspace, shared Twitch/YouTube runtime, aliases, bounded regex/captures, argument parsers, Allow/Deny roles/users/groups, selectable sources, cooldowns, persistence switches, grouping and graph management events/actions | Internal sources require an explicit runtime producer; live whisper authorization remains unverified. See focused comparison below. | P1 |
| Unified chat client | Development: shared Twitch/YouTube history/composer, built-in moderation, emote-name suggestions and authenticated local OBS dock | Rich emotes, command menus, configurable quick actions, highlights, multi-send and full provider moderation synchronization remain. | P1 |
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

## Command and chat comparison

The development branch implements the foundation described in
[Chat and commands](chat-and-commands.md). It also fixes the earlier raw Twitch
starter defect: configured literal patterns and aliases are now enforced, and
unsupported trigger cooldown configuration is rejected visibly. Managed cooldowns
belong in Chat Commands. Fixture coverage is not live-account certification.

| Area | Development implementation | Remaining work relative to Streamer.bot |
| --- | --- | --- |
| Matching and arguments | Token, exact, prefix, contains and bounded regex/captures; case sensitivity; argument parsers; grouping and list inclusion | No additional matching gap identified in the compared settings |
| Permissions | Minimum roles plus Allow/Deny roles, platform users and persisted viewer groups; explicit broadcaster bypass | Live account roles still need provider validation |
| Cooldowns and counters | Alias/platform global and per-user cooldowns; separate reset actions, persistence switches and configurable broadcaster bypass | Cooldowns intentionally reset on restart |
| Command sources | Twitch/YouTube chat; explicit Shared Chat, subscription text, channel/bot whisper sources; bot/internal switches | Live whisper authorization unverified; internal injection has no public endpoint; Kick deferred |
| Automation integration | Saved automation/queue, context/counters/captures, lifecycle triggers and list/get/enable/delete/reset actions | Graph actions do not create/edit definitions |
| Sending | Selected platform; Twitch channel identity | Multi-send, account selection, keyboard routing, native reply threads |
| Suggestions | Built-in emoji and fetched Twitch emote names | Slash/action and managed-command menus; emote images, YouTube/7TV/BTTV/FFZ catalogs |
| Quick actions | Reply, copy, user search, delete, timeout, ban and Twitch unban | Configurable global/user/message/event actions; exact user identity view and richer user cards |
| History and appearance | Session history, platform filters/search, deleted markers, local dock | Highlights, mentions, event feed, pause/scroll controls, external Twitch delete/clear synchronization; configurable fonts, direction, timestamps, avatars, badges and animated emotes |
| Ignore rules | Search and platform filtering only | Per-user and literal/regex ignore rules; hiding detected command messages; explicit policy for hiding versus preventing command execution |
| OBS | Authenticated loopback dock with composer and moderation | Preferences sync, overlay mode and styling controls; direct OBS/CEF verification remains separate |

These remaining items are product gaps, not all blockers for the initial
Twitch/YouTube release. Prioritize permissions, moderation synchronization and
command-management events before cosmetic parity. The richer command settings
and chat features are documented by the official
[commands guide](https://docs.streamer.bot/guide/core/commands) and
[chat guide](https://docs.streamer.bot/guide/extra-features/chat).

## Shipped-artifact evidence and limits

Static REA inspection used a copy of Streamer.bot 1.0.7 without launching it or
reading personal configuration. The executable is an obfuscated, IL-only x64 .NET Framework 4.8.1
assembly (version 1.0.7.0), SHA-256
`25d7d968d60a9905e11d3c1f771788ac60c4235775b685d7a7a186fbb236471b`,
MVID `8fb72992-3b94-47ca-a889-323763c32d38`.

REA's executable artifact inventory completed (7,379 types; 67,496 methods), but
its member parser hit a 64 MiB representation limit. This is an inspection limit,
not evidence that features are absent. A read-only Microsoft
`System.Reflection.Metadata`/`PEReader` inventory, without loading target assemblies,
found command cooldown fields at type token `0x020000fb` (`CooldownLeft`,
`GlobalCooldownLeft`, `UserCooldownLeft`) and properties at `0x020003ca`
(`CommandTrigger`, `GlobalCooldown`, `UserCooldown`). These are metadata anchors,
not a recovered implementation or proof of runtime semantics.

REA completed member inspection of `Streamer.bot.Common.dll`, SHA-256
`971f7a0db0e233c7e4bd5b080373b3473bb5128cbf63806e1ca163d3005469ce`,
MVID `e40999f7-1de9-4311-9e1f-65bdef59fb75`. Its EventType enum declares
`CommandTriggered` (`0x040000ed`), `CommandCooldown` (`0x040000ee`),
`ChatWindowAction` (`0x040000fc`), command add/update/delete (`0x04000148`–`14a`),
Twitch message deletion (`0x04000080`), chat clearing (`0x04000096`) and Shared Chat
session events (`0x040000d0`–`d2`). Tokens apply only to these exact artifacts.
Names corroborate exposed concepts; detailed behavior comes from official docs.

The local REA evidence bundle and metadata inventory are retained under ignored
`.tmp/rea/`; proprietary artifacts and dumps are not repository fixtures. No C#
method bodies were recovered. Static metadata does not establish runtime behavior;
the subsequent UI inspection below provides a separate kind of evidence.

## Runtime UI findings

After explicit user authorization, the distribution ZIP was extracted into
`.tmp/rea/runtime-1.0.7` with fresh local storage. No accounts were connected and
no personal Streamer.bot or OBS configuration was copied or changed. Windows
UI Automation inspected the native application; window captures used PrintWindow
because screen-region capture could include an obscuring application. The
temporary inspection instance was closed afterwards.

The native command workflow was exercised by creating and saving an isolated
command with two aliases. The saved version-7 command document confirmed the
definition, options, source mask, permissions and cooldown fields. Options,
Cooldowns, Sources and User Permissions tabs were inspected, including Normal/Regex
matching, independent bot/internal-message switches and Shared Chat/whisper sources.
This confirms configuration behavior, not delivery or enforcement against live chat.

The desktop opens chat in a separate WebView2 window loading
`https://chat.streamer.bot/feed/chat`. That page is a separately hosted service:
its current UI must not be represented as an immutable part of the 1.0.7 binary.
REA captured passive DOM/accessibility evidence through this instance's loopback
CDP endpoint. UI actions used isolated Windows/DOM helpers. REA's active browser
scenario could not navigate this embedded target; it was not used to claim actions.

Observed additions to the source/documentation comparison:

- A dense command table shows aliases, matching location, cooldowns and enabled
  state; its editor separates options, sources/cooldowns and permissions. Our
  command cards and longer scrolling dialog work, but a compact table and grouped
  editor sections would scale better to larger command libraries.
- Chat has separate combined-chat and event tabs, a compact composer and a
  navigation panel for preferences. Preferences cover typography, message order,
  alternating rows, platform icons, avatars, badges, animated emotes and timestamps.
- Platform preferences expose sender-account selection, user/role colors and
  independent event visibility/highlights in chat and the event feed. Twitch also
  exposes pronoun and GIF preferences. Their presence does not prove every event
  can be received by this offline instance.
- Quick actions have four scopes (global/message/user/event), ordering and fields
  for label, target action, icon, platform, color, menu placement and extra arguments.
  A local blank action was added to inspect this editor; no automation was executed.
- Highlights include role/mention/first-message categories, custom text/regex rules,
  per-user highlights and exclusions. Ignores include users, detected command
  prefixes and prefix/contains/regex rules. An isolated ignore rule was saved and
  remained present after navigation; a font-size change also survived navigation.
- Dock settings expose separate chat/event URLs and settings synchronization.
  Overlay preferences include visible-message bounds, expiry, direction, reload
  behavior, event/timestamp visibility and a generated-message preview. These
  correspond to a dedicated chat-feed presentation workflow, distinct from our
  general overlay editor and current control dock.

Runtime evidence anchors: chat `ev_91c2982df2336380b84ac8835c5bb6932f8ed3c2b1ba7a1c5418614c9ccd878d`,
saved ignore rule `ev_ab9ac3270d8662d45d5fa98643b98c4bad3507e24f19c0c2c2a2917163f584ca`,
quick-action editor `ev_2119b93ab9da1083f111297edca8305f8c910e1e6dd9f8a2ea1eccd29404444e`.
Captures, UI trees, the evidence bundle and temporary definitions remain under
ignored `.tmp/rea/`. External sends, moderation, provider-native replies and
authenticated emote catalogs were not tested against Streamer.bot accounts.

## Recommended sequence

1. Finish live authorization checks for managed commands and unified Twitch/YouTube chat.
2. Add advanced command permissions, management events/actions and moderation synchronization.
3. Add rich emotes, command menus and configurable chat actions; keep Kick separate.
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
