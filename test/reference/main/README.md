# Main reference captures

Capture these screens from the frozen `main` reference with a 1440x900 window,
100% scaling, the bundled Inter font, and deterministic fixture data:

```text
app-empty.png
app-project-loaded.png
file-menu.png
edit-menu.png
project-panel.png
automation-editor-empty.png
automation-editor-complex.png
automation-node-selected.png
profile-editor.png
settings.png
integrations.png
obs-workspace.png
twitch-workspace.png
youtube-workspace.png
moderation-workspace.png
variables.png
queues.png
overlays.png
logs.png
diagnostics.png
unsaved-dialog.png
about.png
updater.png
```

Flutter captures belong in the matching `test/reference/flutter/` directory.
Use `tools/visual_parity/compare.mjs` for each pair and retain the JSON report
and diff artifact outside the committed fixture set.

The currently captured frozen-reference screens are:

```text
app-empty.png
settings.png
updater.png
automation-editor-complex.png
integrations.png
queues.png
variables.png
viewer-variables.png
```

The Flutter catalog additionally captures `diagnostics.png`, `logs.png`, and
`about.png`; the frozen Electron build used for this comparison does not expose
a `Tools` group, so those three reference screens are not available from it.

Regenerate the available reference screens from the local frozen Electron build
with:

```powershell
node tools/visual_parity/capture-main-reference.cjs
```

The command expects the frozen build at `.tmp/main-reference`; it uses an
isolated temporary user directory and a 1440x900, 1x DevTools viewport. Some
plugin screens are only captured when that reference build exposes the plugin
in its catalog.

The deterministic Flutter harness can produce its empty-shell capture with:

```powershell
corepack yarn visual:flutter
```
