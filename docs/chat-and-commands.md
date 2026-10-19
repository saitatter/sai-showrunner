# Chat and managed commands

These features are on the development branch after v2.0.0. Twitch and YouTube
are included; Kick is a separate future integration.

## Commands

Save an automation, open **Chat Commands**, and choose **New command**. Select
the automation and queue, then configure a pattern, aliases, platforms, permission
and cooldowns. Commands run independently of active profiles. Avoid also connecting
the same automation to a raw chat trigger unless two executions are intended.
Raw Twitch chat triggers accept all messages when their optional Match field is
empty; a configured pattern enforces the chosen filter mode.

The first matching enabled command wins, including when its permission or cooldown
rejects execution. Use the up/down buttons to set priority. Command mode requires
a token boundary (`!go` does not match `!good`); Exact, Starts With and Contains
are literal alternatives. Case sensitivity is optional. Argument parsing supports
words, quoted strings with escapes, or the entire remainder. Malformed quoted
arguments and insufficient arguments are rejected before reserving cooldowns.

Permissions use provider roles: everyone, subscriber/member, VIP, moderator and
broadcaster. Moderators and broadcasters satisfy subscriber and VIP restrictions.
User identity includes its platform. Global cooldowns span aliases and platforms;
user cooldowns span aliases for that platform/user. Cooldowns also apply to the
broadcaster and reset when the application restarts. Bot-account messages are
excluded using configured account identities, rather than a message-supplied flag.

Accepted, queued, failed and per-user counters persist separately from authoring
definitions. A queued count confirms enqueueing, not successful graph completion;
inspect Queues for execution results. Counters are reserved before enqueueing and
remain consumed if enqueueing fails. Reset counters does not reset cooldowns.

Definitions are in `chat-commands.json` (version 1); counters are in
`state/chat-command-counters.json`. Unsupported or malformed files fail visibly
without being overwritten. Secrets do not belong in either file. Graph context
contains the normalized message/user/platform values, matched command, arguments
and counters; the same values are available under `event` and `trigger`.

## Unified chat and OBS dock

**Chat** keeps a bounded session history from both connected providers, with search,
platform filtering, reply/copy and moderation actions. Reply selects the destination
and inserts a mention; it does not create a provider-native reply thread. Sending
targets the selected platform. Messages appear when received from the provider,
without speculative local echoes. Clearing history keeps replay deduplication.
Twitch sends and moderation use the authenticated channel account; switching to
a separate bot sender is not yet exposed in this workspace.
For YouTube, the active provider worker's chat takes precedence over the saved
liveChatId, including a broadcast discovered through the YouTube workspace.

Twitch global/channel emote names can be loaded with **Load Twitch emotes**.
Built-in emoji shortcuts work on either platform. Emote images and third-party
catalogs are not yet supported. Paid YouTube messages use their dedicated event
streams and appear as text. YouTube deletion events and successful local deletions
update history; external Twitch moderation synchronization is still open work.

Use **Copy OBS dock URL**, then OBS **Docks > Custom Browser Docks**. The dock is
served locally by ShowRunner, includes history/composer/moderation and requires
ShowRunner to stay open. Its URL is stable across restarts and contains a private
token in the fragment. Keep the full URL private. The token is stored through the
desktop secret store; it is not an OAuth token. **Stop dock** disables automatic
restoration. This is a control dock, not a transparent stream overlay.

## Accounts and validation boundary

Use the existing Twitch and YouTube settings; no new API key is needed for the
dock. Twitch deletion needs `moderator:manage:chat_messages`; reconnect an account
authorized before that scope was added. Moderation requires the authenticated
identity to match the moderator used by the API and to hold channel permissions.
YouTube needs an active `liveChatId` and a suitably authorized account. Its quick
timeout is temporary (60 seconds); unban requires a ban ID and remains in the
YouTube workspace. Permission failures remain visible and preserve composer text.

Fixtures test matching, role enforcement, cooldown concurrency, persistence,
provider routing, moderation request bodies, real queue dispatch, native UI and
the Chromium dock. They do not certify live authorization or account privileges.
Use isolated storage and portable OBS for further tests; no personal profiles or
live configuration were modified by these fixtures. See [live testing](testing/live-services.md).

For remaining Streamer.bot differences and artifact evidence, see
[the comparison](streamerbot-comparison.md).
