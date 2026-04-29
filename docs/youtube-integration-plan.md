# YouTube Integration Plan

SAI Showrunner is an AGPL-3.0 fork of CastMate. The YouTube work should follow the existing CastMate plugin architecture instead of adding a separate service layer. The Twitch plugin is the primary reference for auth, resources, triggers, overlays, and renderer registration.

## Goals

- Add a first-party YouTube plugin with the same UX shape as Twitch.
- Support one-click browser authentication from the desktop app.
- Ingest live chat for the active channel broadcast.
- Expose YouTube events as CastMate triggers and state so they can drive automations, overlays, and timelines.
- Keep the integration modular enough to later share normalized platform events with external SAI services.

## Architecture

The plugin should live under `plugins/youtube` with the same split used by Twitch:

- `plugins/youtube/main`: OAuth, API client, polling loops, resources, actions, triggers, state.
- `plugins/youtube/renderer`: settings panels, account status, trigger configuration UI.
- `plugins/youtube/shared`: shared schemas and event payload types.
- `plugins/youtube/overlay`: overlay-facing components only when YouTube-specific visuals are needed.

Core services:

- `YouTubeAccount`: account resource based on CastMate account storage patterns.
- `YouTubeAuthService`: opens a browser window, handles OAuth redirect, stores access and refresh tokens, refreshes tokens before expiry.
- `YouTubeAPIService`: wraps YouTube Data API calls and centralizes quota/backoff behavior.
- `YouTubeLiveChatService`: resolves the active broadcast, discovers `liveChatId`, polls `liveChat/messages`, and emits normalized internal events.
- `YouTubeViewerCache`: caches author/channel display names and avatars where API payloads are incomplete.

## OAuth

Use Google OAuth 2.0 authorization-code flow with PKCE.

Required MVP scopes:

- `https://www.googleapis.com/auth/youtube.readonly`
- `https://www.googleapis.com/auth/youtube.force-ssl`

Implementation notes:

- Reuse the Twitch auth pattern where Electron opens a login window and captures the redirect.
- Prefer a local loopback redirect URL if compatible with Google OAuth desktop app credentials.
- Store refresh tokens with the same encrypted account/resource mechanism already used by CastMate.
- Add explicit UI states: disconnected, connecting, connected, token expired, quota limited.

## MVP Events

Triggers:

- `youtube.chat.message`: every live chat message.
- `youtube.chat.command`: chat messages matching a command prefix.
- `youtube.super_chat`: paid message.
- `youtube.super_sticker`: paid sticker.
- `youtube.membership`: new membership, upgrade, or milestone message.
- `youtube.subscription`: public subscriber event when available.

State:

- `youtube.channel`: selected channel metadata.
- `youtube.broadcast`: active broadcast id, title, live status.
- `youtube.liveChat`: live chat id, polling interval, last received message time.
- `youtube.latestMessage`: latest normalized chat message.

Normalized message shape:

```json
{
	"id": "youtube-message-id",
	"type": "youtube.chat.message",
	"platform": "youtube",
	"receivedAt": "2026-04-29T00:00:00.000Z",
	"actor": {
		"id": "channel-id",
		"name": "channel-id",
		"displayName": "Viewer Name",
		"avatarUrl": "https://..."
	},
	"payload": {
		"message": "hello chat",
		"isModerator": false,
		"isMember": false,
		"isOwner": false
	}
}
```

## UI Work

- Add a YouTube section to the left navigation beside Twitch.
- Add account connection controls with a single `Connect YouTube` action.
- Show active broadcast and live chat connection status.
- Add trigger editors for chat message, command, super chat, super sticker, and membership events.
- Add quota/backoff warnings that explain when polling is paused.

## Implementation Tasks

1. Scaffold `plugins/youtube` workspaces and register the plugin in app loading.
2. Add shared event schemas and normalized payload types.
3. Implement `YouTubeAccount` and OAuth login window with token persistence.
4. Implement API client with refresh-token support and quota-aware retries.
5. Implement active broadcast discovery and live chat polling.
6. Register MVP triggers and plugin state.
7. Add renderer settings/status UI.
8. Add command filtering and trigger configuration UI.
9. Add tests or local mocks for auth state, polling transform, and trigger emission.
10. Document setup requirements for Google OAuth credentials.

## Later

- YouTube moderation actions.
- Polls, likes, channel statistics, and stream health.
- Per-channel profiles and multiple account support.
- Unified platform event bridge for Twitch, YouTube, and external SAI services.
- Overlay widgets specialized for super chats, memberships, and chat goals.
