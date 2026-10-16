# Twitch and portable OBS stability — 2026-10-16

## Live results

All OBS operations used the workspace portable executable listening on 4456.
The fixture verifies the listener's executable path before connecting. The main
OBS instance was not used.

| Probe | Result | Evidence |
| --- | --- | --- |
| App sends chat through compiled graph | PASS | Six successful `is_sent` responses and six matching EventSub IDs |
| Forced Twitch socket disconnect | PASS | New real connection, new subscriptions, subsequent three messages delivered |
| Burst delivery and graph completion | PASS | Two batches of three messages; expected order, six distinct IDs, six completed graphs |
| Announcement | PASS | Real Helix request accepted |
| Timeout on dedicated `tattcore` account | PASS | 30-second timeout, read-back, typed EventSub timeout, immediate removal and empty ban list |
| Ban on `tattcore` | PASS | Read-back, typed EventSub ban, immediate unban and empty ban list |
| Stream title | PASS | Temporary QA title, read-back, original title restored and verified |
| Browser overlay reconnection | PASS | Three bridge restarts on the same URL; exactly one subscriber after each restart |
| Rendering after reconnection | PASS | Three graph messages per restart, changed real OBS PNG; third capture visually inspected |
| Missing OBS source | PASS | Real OBS error 600; compiled graph did not enter the following node |

Twitch evidence is in ignored `.tmp/twitch-stability-1792121942571/report.json`
and `.tmp/twitch-actions-1792122086867/report.json` under the Flutter package.
OBS evidence is in `.tmp/chat-overlay-proof-1792121991144/`: report, before/after
PNGs, and PNGs for each of the three reconnect cycles. Reconnect rendering used
local fixture messages; real Twitch receiving was tested separately above and in
the [earlier complete live proof](twitch-live-2026-10-16.md).

## Fixed defects

- EventSub now deduplicates notification IDs with a bounded cache, tolerates
  malformed JSON, handles Twitch's planned session handover without recreating
  subscriptions, reconnects silent sockets on the keepalive deadline, times out
  missing welcome frames, and cancels unfinished starts when stopped.
- Browser connections share an in-flight promise, retain connected status on
  repeated connect, settle cancellation before open, and ignore stale sockets.
  Tests now instantiate the production transport with a WebSocket fixture.
- OBS ignores duplicate/late responses, disconnects broken sockets, and includes
  the request name in timeout errors. A local WebSocket test verifies a timeout
  stops the compiled graph and that subsequent requests still work.
- Corrected Helix requests for ban/timeout (`data` wrapper), stream marker
  (`user_id`, `description`), prediction/poll/commercial (broadcaster in JSON),
  and clip creation (`has_delay` in the query). Added exact contract assertions.
- A chat response with HTTP success but `is_sent: false` now fails the action
  with Twitch's drop reason instead of reporting successful execution.

Protocol references: [Helix API](https://dev.twitch.tv/docs/api/reference/),
[EventSub WebSocket lifecycle](https://dev.twitch.tv/docs/eventsub/handling-websocket-events/).

## Validation and limits

715 Flutter tests passed; six opt-in live tests skipped in the default run.
98 renderer/tooling tests passed, overlay build and typechecking passed, and
Flutter analysis was clean. Targeted transport/action tests also passed after
the last timeout-message improvement.

The configured channel is offline and Twitch returned an empty
`broadcaster_type`. Reading custom rewards returned 403. Poll, prediction and ad
schedule reads were accepted, which does **not** prove their write operations or
eligibility. No actual ads, paid subscriptions, Bits, raids, clips, markers,
polls, predictions or redemptions were generated. Those remain live integration
coverage gaps. Clips/markers require a suitable live stream (markers also need
VOD enabled); monetized features require the corresponding channel eligibility.
These are not resolved by supplying another client secret to this Public app.

## Repeat

With portable OBS already running and the renderer built:

```powershell
./scripts/test-live-twitch-overlay.ps1 -LocalPrecheck -Stability
```

This uses local messages and restarts the browser connection three times.
The live Twitch script below makes public test posts and temporarily moderates
the explicitly selected dedicated account; it refuses an existing restriction:

```powershell
./scripts/test-live-twitch-stability.ps1 -TestAccount tattcore
```

Both use the ignored `test/live/connections.local.yml` credentials. Do not run
another EventSub fixture simultaneously. Reports contain no tokens/passwords.
