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
selected actual provider roles, platform-qualified users (`twitch:123`, `youtube:UC...`) and viewer
groups are alternatives. An empty Allow rule permits everyone who meets the minimum;
an empty Deny rule denies nobody. Explicit roles use actual badges; only the
minimum permission applies the moderator/broadcaster hierarchy. Existing Viewer Data groups supply membership;
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

Use **Load twitch/youtube emotes** for the selected composer platform. Twitch
native fragments render provider emotes directly; loaded catalogs add names and
images from Twitch global/channel, 7TV, BetterTTV and FrankerFaceZ (Twitch only).
7TV/BTTV use the selected platform's configured channel ID. Built-in emoji work
without accounts. Public catalogs are cached for 15 minutes; provider failures
are reported separately and do not prevent other catalogs loading.

Emote names match case-sensitively in messages. Native fragments take precedence,
then Twitch > 7TV > BTTV > FFZ, with channel entries ahead of globals. Images use
approved HTTPS CDN hosts, preserve text for copy/accessibility and fall back to
text on failure. Disabling animation chooses a static image where available;
animated entries without a supplied static asset fall back to their name.
YouTube's public live-chat API does not expose a native custom-emoji catalog or
Super Sticker image URLs, so those remain text; Unicode and third-party catalogs
still work. See [YouTube's resource contract](https://developers.google.com/youtube/data/live/reference/rest/v3/liveChatMessages).

Paid YouTube messages use their dedicated event streams. YouTube deletion events
and successful local deletions update history. External Twitch message deletion,
room clear and user-message clear update history scoped to their channel. Bounded
session tombstones also handle deletion arriving before the message; clear events
use provider timestamps to distinguish late old messages from new ones. YouTube
ban events target `bannedUserDetails.channelId`, and deletion/tombstones are scoped
to the live chat. Malformed user-clear events never clear the entire room.

Use **Copy OBS dock URL**, then OBS **Docks > Custom Browser Docks**. The dock is
served locally by ShowRunner, includes history/composer/moderation and requires
ShowRunner to stay open. Its URL is stable across restarts and contains a private
token in the fragment. Keep the full URL private. The token is stored through the
desktop secret store; it is not an OAuth token. **Stop dock** disables automatic
restoration. This is a control dock, not a transparent stream overlay.

## Configurable actions and event feed

Open **Chat actions** to add, edit, disable, reorder or remove a shortcut to a
saved automation and queue. Choose Global, Message, User or Event scope, platforms,
label, icon, color and literal `name=value` arguments. Global buttons follow the
composer platform and appear in `/action:<id>` completion; optional trailing text
is available as `actionInput`. Message/user actions appear in message menus;
event actions appear beside feed entries. Selected targets must still exist and
message targets must not have been deleted. Unknown/disabled actions fail visibly.

Graphs receive the selected message or public event context plus `chatActionId`,
`chatActionScope`, `actionArguments` and `actionInput`. Context is also available
under `event` and `trigger`. The same saved-graph queue executor serves commands
and quick actions; shortcuts do not embed execution code in their definitions.
Definitions are in `settings/chat-actions.yaml` (version 1). Arguments are ordinary
configuration, so do not put credentials in them. Unsupported files are preserved.
The authenticated dock exposes enabled shortcuts, not automation files or arguments.

The **Events** view collects bounded session entries for Twitch follows,
subscriptions/gifts, redemptions, bits, raids, bans/timeouts and YouTube membership,
Super Chat and Super Stickers. Platform/search filters and pause apply to this
view. Only curated public fields enter the feed; whispers and command lifecycle
payloads are excluded. Clear local history also clears the event feed, retaining
replay deduplication. This feed represents delivered provider events, not an audit
of every action performed on the platform.

## Preferences, highlights and ignores

Open **Chat preferences** for shared font/size, timestamps, history direction,
alternating rows, platform icons, role labels and the animated-emote preference.
The dock receives these settings and can edit basic display options. Highlights
match case-insensitive text/mentions, platform-qualified users or selected roles.
Deleted messages are never highlighted.

Ignore rules match platform-qualified users, literal prefixes, literal contained
text or bounded regex. **Hide detected managed commands** matches enabled commands
on their configured platforms and sources. Rules affect both native history and
the dock; changing preferences re-evaluates the retained session history.
By default hiding does not prevent automation. Enable **Also prevent ignored
messages from running commands** to block managed command dispatch as well.
This policy does not disable separately configured raw provider graph triggers.
Regex failures are visible; affected messages stay hidden and the explicit block
policy controls dispatch. Unsupported saved preferences are preserved and editing
is refused until the file is repaired. Preferences live in `settings/chat.yaml`.

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
