# ShowRunner developer notes

## Setup

The desktop application targets Windows and is developed with Flutter stable.

```powershell
Push-Location packages/showrunner-flutter
flutter pub get
flutter analyze
flutter test
Pop-Location
```

Build a release archive with:

```powershell
.\scripts\package-flutter-windows.ps1 -Version 1.0.0-beta1
```

Node.js and Yarn are optional and are used only for the OBS browser-overlay
surface:

```powershell
corepack enable
yarn install
yarn overlay:test
yarn overlay:build
```

## Architecture

- `packages/showrunner-flutter/lib/schema` contains the canonical V2 data model.
- `packages/showrunner-flutter/lib/editor` contains the graph editor and its
  schema adapters.
- `packages/showrunner-flutter/lib/runtime` contains expression evaluation,
  graph execution, profile runtime, queues, and recovery diagnostics.
- `packages/showrunner-flutter/lib/plugins` contains the Dart plugin contracts
  and provider implementations.
- `packages/showrunner-flutter/lib/persistence` reads and writes YAML/JSON
  documents without changing their schema.
- `packages/showrunner-obs-overlay` is the HTML browser-source runtime required
  by OBS; it is not a desktop renderer.

Automations and inline profile graphs must contain:

```yaml
schemaVersion: 2
graph:
  nodes: []
  edges: []
  entryNodeId: ""
subgraphs: []
dataWires: []
variableNodes: []
triggerNodes: []
```

Profile trigger entries contain trigger metadata plus an `automation` object
using the same V2 document. Invalid documents are reported to the user instead
of being rewritten.

## Engineering rules

- Add new behavior to the Flutter/Dart application first.
- Keep schema parsing strict and explicit; do not add alternate document forms.
- Keep missing plugin nodes visible in the editor so a document remains
  inspectable.
- Keep expression evaluation inside the runtime DSL; do not introduce dynamic
  code execution.
- Keep queues as schedulers for graph work, not as a separate automation model.
- Preserve upstream AGPL notices and use Conventional Commits.

## Verification

Before submitting a change to the desktop app:

```powershell
Push-Location packages/showrunner-flutter
flutter analyze
flutter test
flutter build windows --debug
Pop-Location
.\scripts\smoke-flutter-windows.ps1 -Configuration Debug
```

For release verification, run the packaging script and its archive smoke suite.
The CI workflow runs the same Flutter checks on Windows.

For overlay changes, also run `yarn overlay:build` and the browser overlay
protocol tests under `packages/showrunner-obs-overlay`.

## References

- [OBS WebSocket Protocol](https://github.com/obsproject/obs-websocket/blob/master/docs/generated/protocol.md)
- [Twitch Authentication](https://dev.twitch.tv/docs/authentication)
- [Twitch API](https://dev.twitch.tv/docs/api/)
- [Twurple Docs](https://twurple.js.org/)
