# ShowRunner Developer Notes

## Setup

ShowRunner is a Yarn 4 monorepo targeting Node.js 20+.

```powershell
corepack enable
corepack yarn install
corepack yarn dev
```

Useful commands:

```powershell
corepack yarn test
corepack yarn check
corepack yarn overlay:smoke
corepack yarn build
corepack yarn release:dry-run
```

Windows packaging is the only release target at the moment. Use:

```powershell
$env:CSC_IDENTITY_AUTO_DISCOVERY = "false"
corepack yarn build
```

## Architecture

ShowRunner is an AGPL-3.0 fork of CastMate. Keep upstream license notices intact and prefer small, reviewable changes around existing plugin boundaries.

The automation runtime is graph-only:

- persisted automations use `schemaVersion: 2`;
- stale `sequence` and `floatingSequences` fields are stripped by load-time normalization;
- `ActionResolvers` provide automation sources and context schemas;
- `GraphCompiler` compiles `AutomationGraph` + subgraphs + data wires into a flat `Program`;
- `compileAutomationProgram()` caches compiled programs by graph signature;
- `GraphVM` executes the program with abort support, queue timeouts, debug hooks, and subgraph calls.

Queues are runtime schedulers, not a second automation model. Graph nodes enqueue, start, complete, cancel, and clear queue items. The Queues page should stay observability-focused.

## Automation UI Guidelines

- New features should target the node graph editor first.
- Keep legacy sequence concepts out of public schema and new UI.
- Preserve missing action/trigger nodes visually instead of crashing the editor.
- Expression editor changes must validate inline and avoid JavaScript `eval()`.
- Subgraph calls should expose typed ports from subgraph parameters and outputs.

## Release Prep

Semantic release is configured with squash-commit expansion and GitHub draft releases. Before a beta or stable release:

1. Run `corepack yarn test`.
2. Run `corepack yarn check`.
3. Run `corepack yarn overlay:smoke`.
4. Build Windows assets with `corepack yarn build`.
5. Run `corepack yarn release:smoke-artifacts`.
6. Run `corepack yarn release:dry-run`.

For the parallel Flutter Windows artifact, run
`corepack yarn flutter:smoke-windows` after `flutter build windows --release`.
The release workflow also launches the versioned Flutter archive with
`scripts/smoke-flutter-windows.ps1` using an isolated user directory.

For `1.0.0-beta`, confirm that [MIGRATION.md](MIGRATION.md) is current and release notes mention the graph-only automation breaking change.

## References

- [OBS WebSocket Protocol](https://github.com/obsproject/obs-websocket/blob/master/docs/generated/protocol.md)
- [Twitch Authentication](https://dev.twitch.tv/docs/authentication)
- [Twitch API](https://dev.twitch.tv/docs/api/)
- [Twurple Docs](https://twurple.js.org/)
