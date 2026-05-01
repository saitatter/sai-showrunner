# Moderation And Chat Overlay Migration

ShowRunner now owns the user-facing moderation and chat overlay experience. `sai-moderation-docker` remains the moderation backend/API, while the docker-hosted `/dashboard` frontend is kept only as a compatibility fallback.

## Architecture

```text
Twitch / YouTube trigger
-> ShowRunner automation
-> Moderation: Filter Chat Message
-> moderation docker POST /v1/chat-events deliveryMode=decisionOnly
-> condition on approved / verdict
-> Overlays: Push Chat Message
-> Overlay Studio Chat Feed widget
```

The moderation backend still stores queue state, serves `/api/moderation/queue`, accepts `/v1/overrides`, and publishes dashboard websocket updates. ShowRunner consumes those APIs directly in `Integrations -> Moderation`.

## Moderation Action

Use `Moderation -> Filter Chat Message` with normalized chat context:

- `platform`
- `messageId`
- `viewerId`
- `viewerName`
- `message`
- `badges`

The action returns:

- `verdict`
- `status`
- `confidence`
- `category`
- `reason`
- `messageId`
- `approved`
- `blocked`
- `flagged`

For routing, prefer conditions on `approved` or `verdict`.

## Native Queue UI

Open:

```text
Integrations -> Moderation -> Moderation Docker
```

The page provides:

- connection settings and optional API token
- health check and test event
- latest/pending/approved/rejected queues
- manual `Approve`, `Block`, and `False Positive` actions

## Chat Feed Migration

Replace standalone `sai-chat-overlay` browser sources with a ShowRunner overlay:

1. Create or open an overlay in Overlay Studio.
2. Add a `Chat Feed` widget.
3. Configure platform colors, font, background opacity, fade time, max messages, layout, and badges.
4. Add that overlay Browser Source URL to OBS.
5. In automations, route approved messages through `Overlays -> Push Chat Message`.

The widget does not connect to Streamer.bot or moderation docker directly. ShowRunner automations decide what gets rendered.

## Shader Layer Widget

Use `Shader Layer` for complex visual overlays that need procedural motion. Version 1 uses bundled shader presets only:

- `aurora`
- `grid`
- `plasma`

Live-editable params:

- accent and secondary colors
- intensity
- speed
- opacity
- blend mode
- optional text

Remote shader loading is intentionally not part of v1. A future shader editor can add authored local presets while keeping OBS runtime safe.
