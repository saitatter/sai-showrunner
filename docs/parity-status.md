# Surface and parity status

This is the current contract for the Flutter desktop application and its
browser-source companion. It records intentional boundaries and items that
still require an operator or a future implementation.

## Desktop application

The Windows desktop runtime is Flutter/Dart. Automation documents use the
canonical `schemaVersion: 2` graph shape, plugin actions and resources are
registered by the Dart runtime, and the release archive is built from the
Flutter Windows output.

The repository is organized around these runtime surfaces:

- `packages/showrunner-flutter`: desktop UI, persistence, graph runtime, and
  Dart plugin implementations;
- `packages/showrunner-obs-overlay`: the browser source required by OBS;
- `libs/showrunner-schema`, `libs/showrunner-overlay-core`, and
  `libs/showrunner-ws-rpc`: the web protocol boundary used by that source.

## Intentional browser boundary

OBS browser sources need an HTML/WebGL runtime. The overlay remains a Vue/TS
browser product and is not a second desktop renderer. Shader/WebGL rendering,
browser layout, and browser-only widget behavior therefore remain authoritative
in that package. Flutter edits the typed resource fields and preserves the
structured resource data needed by the browser runtime.

This boundary is validated with the overlay protocol tests and Vite build in
addition to the Flutter checks; deleting the browser surface would remove OBS
functionality rather than complete the desktop cutover.

## Current remote-dashboard coverage

The Flutter remote surface supports both sides of the connection negotiation:
the desktop can host shared dashboards and can also connect as a satellite.
Dashboard pages and sections, remote buttons, dashboard labels, state
broadcasts, widget RPC, live config refresh, and resource-slot binding are
covered. The remote button preserves the raised shadow, pressed front movement,
adaptive label sizing, and trigger RPC behavior of the runtime surface.

Unknown remote widget kinds are shown as an explicit placeholder so a dashboard
remains inspectable. A new widget kind still needs a dedicated Flutter renderer
before it can be considered visually equivalent.

## Contract and UI audit

`docs/parity.json` is generated from the frozen `main` tag and now catalogs
renderer source files as well as action, trigger, setting, state, and resource
IDs. The current report has 14 `partial`, 14 `improved`, and 4 `equivalent`
plugin entries, with no missing contract IDs. It intentionally reports
plugin-specific UI contributions that still need Flutter work as `partial`; a
generic manifest page is not counted as pixel parity.

## Release and update limits

The release workflow currently produces and smoke-tests a Windows ZIP archive.
The application can query GitHub releases, detect the matching Windows ZIP, and
open its download URL while reporting available, current, offline, and
downloaded states. A Windows-only installer helper stages a downloaded ZIP,
waits for the current process to close, replaces the bundle, and starts the new
executable. It is unit-tested with an injected launcher; a signed production
installation/rollback test still requires the installed Windows release
environment and is not claimed by the package smoke suite.

The automated smoke suite validates startup, first run, graph/workflow use,
profiles, integrations, overlays, and update-state handling. It does not prove
pixel-perfect rendering or replace the manual checks in
`docs/beta-regression-checklist.md`.

## Evidence

The repeatable checks are:

```powershell
corepack yarn install --immutable
corepack yarn overlay:test
corepack yarn overlay:build
Push-Location packages/showrunner-flutter
flutter analyze
flutter test
flutter build windows --release
Pop-Location
.\scripts\smoke-flutter-windows.ps1 -Configuration Release
.\scripts\package-flutter-windows.ps1 -Version <version>
```
