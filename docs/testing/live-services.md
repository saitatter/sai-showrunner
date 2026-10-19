# Live-service testing and isolation

This is the maintained record of external proof and outstanding limits. Earlier
dated reports are preserved in Git history, not as competing instructions.
Successful local fixtures or action insertion do not validate an external account.

## OBS

Use only the workspace portable OBS executable under .tmp/obs-portable, with its
WebSocket on port 4456. Tests verify the listener's process path and must refuse a
personal instance. Use test resources, restore the previous scene, and remove test
scenes/sources. Never change personal OBS profiles, output settings or recording paths.

A prior complete live run covered the 27 exposed OBS actions and workspace/overlay
flows. Real shader animation, state-bound uniforms and state reacquisition after a
browser reconnect were also demonstrated in portable OBS. These are past proofs,
not a fresh check of every combination. Rapid Studio Mode operations previously
caused native OBS crashes; scripts support isolating those operations for diagnosis.

Repeat from the repository root with `scripts/test-live-obs.ps1`, after setting up
the portable instance and local connection file. Check script options before running
stream/output actions: opt-in scenarios can start recording, streaming or virtual cam.

## Twitch

The desktop Public OAuth flow uses only a Client ID and the exact registered URL
http://localhost:17563/oauth/callback. The token and identity are obtained by login.
Other token/refresh flows have their own credential requirements. Keep all tokens in
ignored connections.local.yml or secret settings; never in screenshots or logs.

Prior live proof covered OAuth identity/scopes, channel/dashboard reads, chat send
and receive, moderation against an explicitly authorized test account, and the
real chat -> compiled graph -> overlay WebSocket -> portable OBS Browser Source path.
A separate stability probe checked reconnect/disposal behavior. EventSub subscription
acceptance is not proof of receiving every event. Channel-point reads returned 403
for the configured channel; reward eligibility and paid/subscription/raid/ad events
must be verified separately when the user authorizes the scenario.

Repeat with scripts/test-live-twitch.ps1, scripts/test-live-twitch-overlay.ps1 and
scripts/test-live-twitch-stability.ps1. A real event must be sent/generated when the
probe requests it; a local fixture is reported separately. Use a dedicated account
for moderation tests. Do not repeat writes just because credentials are present.

## Unified chat and managed commands

The development Chat/Chat Commands workspaces have isolated runtime, HTTP,
Chromium and Windows UI fixtures. This does not extend the earlier live Twitch
evidence to the new client or certify YouTube authorization. No live messages,
bans, timeouts or personal OBS dock changes were made for those fixtures.
See [setup and behavior](../chat-and-commands.md).

Before a live pass, reconnect Twitch if its token predates
`moderator:manage:chat_messages`. The client uses the authenticated channel account
for sends and moderation. YouTube needs an active test broadcast/liveChatId and
an account allowed to send and moderate. Use a separate consenting test account
for timeout/ban tests. Test aliases, unrelated messages, role rejection and
global/user cooldowns using different users; inspect actual Queues execution as
well as command counters. Browser fixtures do not replace an OBS/CEF dock check.

## Other providers and devices

YouTube requires an authorized test channel/liveChatId; memberships and paid events
need real provider conditions. Lighting, BLE sensors, Voicemod, Discord and other
integrations need their own opted-in device/account checks. Local HTTP/Discord/OBS
fixtures prove transport/runtime behavior without validating those external services.
Remote signaling/WebRTC fixtures do not prove a real remote deployment.

The [node setup guide](live-nodes.md) points to the ignored local YAML and versioned
example. All real write scenarios default disabled. Keep liveStatus pending until
that exact scenario has recorded evidence. Unsigned Windows package/install/rollback
proofs run in isolated storage. Downloading a published release and verifying an
installed upgrade remains a separate operator check; local fixtures do not prove
the public release channel.
