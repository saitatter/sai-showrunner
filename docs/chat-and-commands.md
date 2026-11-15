# Chat and managed commands

Twitch, YouTube and Kick are included. Unreleased additions below are validated
with isolated fixtures; live-account validation is a separate step.

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

**Chat** keeps a bounded session history from the connected providers, with search,
platform filtering, reply/copy and moderation actions. The user action filters by
platform-qualified ID, so identical names on different platforms stay separate.
Pause view freezes visible arrivals while collection continues; resume shows them.
Type `!` for enabled, listed commands and aliases on the selected platform, or `/`
for local clear/pause/resume actions. Arrow keys select a suggestion; Tab or Enter
inserts it before sending. These menus are shared with the browser dock. Reply selects the destination
and inserts a mention; it does not create a provider-native reply thread. Sending
targets the selected destinations. Messages appear when received from the provider,
without speculative local echoes. Clearing history keeps replay deduplication.
Twitch sends can use the broadcaster or separately authenticated bot; moderation
uses the authenticated channel account.
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

## Dedicated OBS chat overlay

Add **Chat Feed** to an overlay, set **source** to `unifiedChat`, choose all/Twitch/
YouTube/Kick, and save. Use that overlay's existing **Browser Source URL** in portable
OBS. The widget polls approved public history once per second without a graph
connection or the admin dock token. The existing `automation` source remains
available for manually approved graph pushes; the two sources do not mix.

Configure 1-200 messages, `fadeTime` 0-86,400 seconds (0 keeps messages until they
leave history), horizontal/vertical layout, font/size, background color/opacity,
platform colors and badge labels. Deletions, local clears and changed ignore
preferences replace the displayed snapshot. Expiry also runs locally during a
connection outage. Source changes and widget destruction abort pending reads and
release poll/expiry timers. Authoring preview uses sample messages.

Only a Chat Feed saved with `unifiedChat` may read its widget-specific endpoint.
Access uses the overlay's scoped capability/HttpOnly session, and the server
rechecks the current widget configuration after asynchronous reads. The endpoint
has no send/moderation operations, credentials, raw provider data or private account metadata.
Private/ignored/deleted messages and private moderation events are excluded.
A disabled badge display also omits badge data from the projection. Browser
markup is rendered as literal text. Live OBS/CEF authorization remains a separate
probe from the isolated Chromium fixtures.

## Public user profiles

Choose **User profile** from a message menu in desktop Chat or the OBS dock.
The card shows the provider-qualified ID, public name/login, avatar, badges and
retained session message count (desktop). Twitch metadata loads on demand; use
**Load recent profiles** in the desktop card to enrich up to 100 recent users
across at most 10 channels. The session cache retains at most 500 users and 4,096
badge versions; nothing is added to Viewer Data or authoring documents. Refresh
reloads public metadata. Missing grants or images keep text and role fallbacks
usable. No provider request is made for every incoming message.

YouTube avatars come from live-chat `authorDetails.profileImageUrl`; graphical
role icons represent its owner/moderator/member flags. Twitch uses public profile
images and channel/global badge versions, including Shared Chat source badges.
Image URLs are restricted to supported HTTPS provider CDNs. Email, tokens and raw
user API payloads never enter profiles or dock projections. These display records
never grant command permissions: authorization still uses delivered provider roles
and the platform API. Public metadata may be stale until refreshed.

## Native moderation shortcuts

The message menu in desktop chat and the OBS dock adds Twitch Pin/Unpin, Warn,
Add/Remove VIP and Add/Remove Moderator alongside delete/timeout/ban/unban.
Role choices reflect badges on the received message; Twitch still authorizes
and validates the current role on each request. Warning confirmation requires a
non-empty reason (up to 500 characters). Platform-specific shortcuts are omitted
from YouTube menus; its existing delete/timeout/ban paths remain available.
Broadcaster messages may be pinned/deleted, but the owner is excluded from
user sanctions and role changes. AutoMod held text and warning reasons remain
on private automation events, outside public history and event-feed projections.

## Multi-platform sends and sender accounts

Select Twitch/YouTube/Kick destination chips in desktop Chat, or a platform
combination in the OBS dock. Select **Twitch: broadcaster** or **Twitch: bot** independently.
YouTube uses its configured authorized account; it has no second bot account slot.
The Twitch bot uses its separately encrypted `TwitchAccount/bot` credential and
identity, never a different sender ID on the broadcaster token. A missing/expired
bot grant fails explicitly, without falling back to the broadcaster. Sign in the
bot in Twitch settings and grant `user:write:chat`; implicit tokens need reauthorization
when expired. Moderation continues to use the channel's authenticated actor.

Every target's message limit is checked before sending (500 Twitch, 200 YouTube;
Kick allows 500 grapheme clusters and at most 2048 UTF-8 bytes).
Destination requests run concurrently. Each reports its own result; a partial
failure retains the text and selects only failed destinations for retry. Known
successful targets are not resent. Delivery owns history; no local message echo
is fabricated. A lost network response can leave delivery uncertain; this is not
an exactly-once messaging protocol. Slash shortcuts execute on one platform at a
time, and local `/clear`, `/pause`, `/resume` never become provider messages.
The dock retains authentication and the same bounded, typed request validation.

## Kick connection and live validation

In **Plugins > Kick**, save a Kick Developer client ID and client secret. Register
`http://localhost:53543/oauth/callback` as the OAuth redirect URL, then choose
**Connect Kick** and authorize the broadcaster account. The OAuth flow uses PKCE;
Kick also requires the client secret. Secrets use the application's encrypted
settings store. The verified user ID becomes the broadcaster ID; profile email is
not retained. Token refresh preserves unrelated settings and refuses to overwrite
a replacement account.

Kick's official event API requires a public HTTPS webhook. In Kick Developer,
enable webhooks and register `https://YOUR-HOST/kick/webhook`. Forward only that
route to `http://127.0.0.1:53544/kick/webhook`, using your existing reverse proxy
or tunnel, and save the public URL in Kick settings. A different local port may
be saved before starting. Do not forward the application's admin server or chat
dock. No tunnel/cloud service is created automatically.

Choose **Start listener**. `Running` means the local listener and subscriptions
are ready; it does not certify public reachability. Send a human message from a
second account and verify it in Chat with the Kick filter. A proxy/CDN must allow
Kick's webhook requests through to this route without an interactive challenge.
Stop releases the listener and removes only subscriptions created by that session;
pre-existing subscriptions are reused and retained. An unsuccessful unsubscribe
may leave an orphan that is reused on the next start.

Webhook ingestion checks RSA/SHA-256 signatures against Kick's fetched public key,
refreshes keys for rotation, rejects old/future timestamps and deduplicates both
delivery IDs and logical messages. Unsigned, malformed, foreign-channel and
unsupported subscription payloads never become commands. Body size, concurrent
verification and replay memory are bounded. Provider events are namespaced as
`kickChatMessage`, `kickUserBanned` and `kickUserTimedOut`, so Twitch triggers do
not receive Kick messages. Kick viewer identities are stored under `kick`.

Sending supports **Kick: user** and **Kick: app bot**. The latter is the bot
created for the Kick Developer application, using the same authorized channel
token; it is not a second personal bot-account credential. For bot mode, create
the application's bot in Kick Developer. The API selects its token's channel;
an explicit target broadcaster ID is used only for user mode.

Graph nodes and message menus provide send, delete, timeout, ban and unban. Timeout
durations are minutes (1-10080); the 60-second shortcut sends one minute. Only a
confirmed `is_sent` response reports send success. Request failures retain drafts;
there is no speculative local echo. Successful deletes update local history and
OBS projections. The public API currently has no message-deleted event, so deletes
performed by another client are not guaranteed to update our retained history.

Kick avatars use approved Kick HTTPS image hosts; roles come from signed identity
badge types and the broadcaster ID, not display names, labels or verification
marks. Native emote tokens remain literal and built-in emoji autocomplete works;
there is no official emote-catalog API used here. Provider badge image URLs are
not supplied by the event API, so role badges use our existing label/icon fallback.
Bot filtering uses a signed bot badge when present. If the app bot is not marked
by Kick, add its `kick:USER_ID` to ignored users and enable **Prevent ignored
commands** before testing automations that could answer their own messages.

The sign-in requests `user:read`, `chat:write`, `events:subscribe`, `moderation:ban`
and `moderation:chat_message:manage`. A real client ID/secret, app bot for bot mode,
public webhook route and a dedicated second account are needed for live proofs.
Do not enable mutation scenarios until their target and effects are authorized.
The generated `test/live/connections.example.yml` includes empty Kick settings;
copy it to the ignored `connections.local.yml` for isolated node probes. Never
commit filled credentials or post them in chat.

API contracts: [OAuth](https://docs.kick.com/getting-started/generating-tokens-oauth2-flow),
[chat](https://docs.kick.com/apis/chat),
[webhook security](https://docs.kick.com/events/webhook-security),
[event types](https://docs.kick.com/events/event-types).

## Twitch lifecycle and moderation nodes

Polls expose Get Polls (IDs or cursor pagination), Terminate Poll and Archive Poll.
Predictions expose Get Predictions, Lock, Resolve and Cancel. Transition nodes
require the exact poll/prediction ID; Resolve additionally requires the winning
outcome ID. Get results keep Helix data and pagination; lifecycle triggers
include option IDs, votes/points and timestamps. Progress is a separate trigger.

Pin/Unpin Chat Message use a message ID. Pin duration is optional (until stream
ends), or 30-1800 seconds. Adding/removing VIPs and moderators uses viewer IDs;
these actions never silently demote another role. Warn Viewer requires a reason
(up to 500 characters). Allow/Deny AutoMod Message acts on a held message ID.
Warning sent/acknowledged and AutoMod held/updated/settings/terms triggers expose
moderator IDs and details on dedicated automation events. Held text is private
moderation data; it does not become public chat history or dock content.

Reauthorize the channel account to grant `channel:manage:vips`,
`channel:manage:moderators`, `moderator:manage:warnings`,
`moderator:manage:automod` and `moderator:manage:automod_settings`.
Polls/predictions use their existing manage scopes and Twitch account eligibility.
Pins use `moderator:manage:chat_messages`. A scope alone does not grant channel
roles. Provider refusals propagate without retrying lifecycle or role mutations.
See the official [poll](https://dev.twitch.tv/docs/api/reference/polls/),
[prediction](https://dev.twitch.tv/docs/api/reference/predictions/),
[chat](https://dev.twitch.tv/docs/api/reference/chat/) and
[moderation](https://dev.twitch.tv/docs/api/reference/moderation/) contracts.

Channel tools include Get/Set Channel Tags (maximum 10 alphanumeric tags,
25 characters each). Set replaces the list; `[]` clears it. Clip Download URLs
accepts 1-10 clip IDs and returns Twitch's temporary download links without
fetching the files. Reauthorize for `channel:manage:clips`; the editor ID must
identify the authenticated broadcaster/editor. Do not persist signed URLs as
long-lived media references.

Guest Star (Twitch Stream Together, beta API) exposes get/create/end session,
get/send/delete invites and assign/delete guest slots. Session/guest/slot IDs
must be explicit; no automatic selection or silent guest replacement logic is
added locally. Twitch itself replaces a guest occupying the assigned slot.
Deleting a slot optionally reinvites the guest. Reauthorize the broadcaster for
`channel:manage:guest_star`. Creating a session requires the broadcaster present
in Twitch's call interface; these nodes do not implement a video-call client.
See [Guest Star](https://dev.twitch.tv/docs/api/reference/guest-star/) and
[Clips](https://dev.twitch.tv/docs/api/reference/clips/) for eligibility and API limits.

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
