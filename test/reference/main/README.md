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
