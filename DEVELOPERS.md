## Setup

Pull Requests are on hold until a CLA can be worked out.

We're currently developing on Node.js 20+ (see `.nvmrc`).

This repo is a mono repo managed by **Yarn 4** (Berry) workspaces. Make sure Corepack is enabled:

```powershell
corepack enable
```

Install dependencies:

```powershell
corepack yarn install
```

ShowRunner has a custom Vite plugin to handle mono-repo builds:

```powershell
corepack yarn run setup-vite
```

To start in development mode:

```powershell
corepack yarn dev
```

To build into an installer:

```powershell
corepack yarn build
```

## Useful Documentation Links

-   [OBS Websocket Protocol](https://github.com/obsproject/obs-websocket/blob/master/docs/generated/protocol.md)

-   [Twitch Authentication](https://dev.twitch.tv/docs/authentication)

*   [Twitch API](https://dev.twitch.tv/docs/api/)

-   [Philips Hue](https://developers.meethue.com/develop/get-started-2/)

-   [Twurple Docs](https://twurple.js.org/)
