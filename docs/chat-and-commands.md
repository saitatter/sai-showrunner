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
are literal alternatives. Regex supports numbered/named capture groups, runs in a
separate isolate and is terminated after 250 ms; patterns are limited to 2,048
characters and input to 4,096. Case sensitivity is optional. Argument parsing supports
words, quoted strings with escapes, or the entire remainder. Malformed quoted
arguments and insufficient arguments are rejected before reserving cooldowns.

Permissions use provider roles: everyone, subscriber/member, VIP, moderator and
broadcaster. Moderators and broadcasters satisfy subscriber and VIP restrictions.
The minimum role is combined with an optional Allow/Deny rule. Within that rule,
selected roles, platform-qualified users (`twitch:123`, `youtube:UC...`) and viewer
groups are alternatives. An empty Allow rule permits everyone who meets the minimum;
an empty Deny rule denies nobody. Existing Viewer Data groups supply membership;
unqualified group user IDs are Twitch IDs. A missing group fails closed.

Global cooldowns span aliases and platforms; user cooldowns span aliases for that
platform/user. Both reset at application restart. Broadcasters obey permissions
and cooldowns unless **Broadcaster bypass** is enabled; a bypassed invocation still
reserves the next cooldown for other viewers. Bot/internal inputs are ignored by
default, using configured account identities rather than message-supplied flags.
Select Chat, Shared Chat, Whisper, Bot Whisper, Subscription or Internal sources
explicitly. Whisper sources dispatch commands privately and never enter public
history or the dock. Internal inputs require opting in to both the source and flag.
Group labels organize command search; Include in list controls graph list results.

Accepted, queued, failed and per-user counters persist separately from authoring
definitions. A queued count confirms enqueueing, not successful graph completion;
inspect Queues for execution results. Counters are reserved before enqueueing and
remain consumed if enqueueing fails. Reset counters does not reset cooldowns.
Separate controls reset user counters or cooldowns (all or one platform:user ID).
Persistence switches independently control total and per-user counters on restart;
counts remain available for the current session when persistence is disabled.

The **Chat Commands** graph plugin exposes List, Get, Enable/Disable, Delete and
counter/cooldown reset actions. Triggers report additions, updates, deletion,
accepted commands, cooldowns, permission/configuration rejection, enqueue failure
and resets; each can filter by command ID. Disabling this plugin also disables
managed command dispatch. Regex captures are in the `captures` context map.

Definitions are in `chat-commands.json` (version 1); counters are in
`state/chat-command-counters.json`. Unsupported or malformed files fail visibly
without being overwritten. Secrets do not belong in either file. Graph context
contains the normalized message/user/platform values, matched command, arguments
and counters; the same values are available under `event` and `trigger`.

## Unified chat and OBS dock

**Chat** keeps a bounded session history from both connected providers, with search,
platform filtering, reply/copy and moderation actions. The user action filters by
platform-qualified ID, so identical names on different platforms stay separate.
Pause view freezes visible arrivals while collection continues; resume shows them.
Type `!` for enabled, listed commands and aliases on the selected platform, or `/`
for local clear/pause/resume actions. Arrow keys select a suggestion; Tab or Enter
inserts it before sending. These menus are shared with the browser dock. Reply selects the destination
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
update history. External Twitch message deletion, room clear and user-message clear
also update history, scoped to the originating channel.

Use **Copy OBS dock URL**, then OBS **Docks > Custom Browser Docks**. The dock is
served locally by ShowRunner, includes history/composer/moderation and requires
ShowRunner to stay open. Its URL is stable across restarts and contains a private
token in the fragment. Keep the full URL private. The token is stored through the
desktop secret store; it is not an OAuth token. **Stop dock** disables automatic
restoration. This is a control dock, not a transparent stream overlay.

## Accounts and validation boundary

Use the existing Twitch and YouTube settings; no new API key is needed for the
dock. Twitch deletion needs `moderator:manage:chat_messages`; reconnect an account
authorized before that scope was added. Private command sources additionally need
`user:read:whispers`; reauthorize both the channel and a separately configured bot.
Bot whispers use their own authenticated EventSub connection, whose status is
shown in Chat. Shared Chat and subscription text use existing chat notifications. Moderation requires the authenticated
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
