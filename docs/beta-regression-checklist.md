# V1 Beta Regression Checklist

Use this before a beta build after graph editor, queue, integration visibility, or starter-template changes.

## Automation Starters
- [ ] Open `File -> New Automation From Starter`.
- [ ] Verify paid alert, scene banner, OBS scene change, Twitch chat command, moderation review, and stream plan starters are visible.
- [ ] Create each starter and confirm the graph opens with a valid entry node.
- [ ] Confirm resource/widget/queue fields that need user selection are empty, not prefilled with stale IDs.

## Queue Workflows
- [ ] Create `Paid Event -> Add to Alerts Queue` and `Queue Item Started -> Paid Alert Overlay -> Sound -> Complete`.
- [ ] Create `Scene Begin -> Add to Scene Queue` and `Queue Item Started -> Scene Banner -> Shader Layer -> Complete`.
- [ ] Confirm queue starter graphs use `Add to Queue`, `Queue Item Started`, and `Complete Queue Item` nodes.
- [ ] Run a test queue item and confirm the worker graph completes or reports a visible node error.

## Data Wires And Conversions
- [ ] Try connecting incompatible data ports directly and confirm the invalid hover/drop feedback appears.
- [ ] Confirm the incompatible wire is not created.
- [ ] Add an explicit conversion node and confirm the converted output can connect to the target port.
- [ ] Open an automation with stale data wires and confirm the health panel can select and clean them up.

## Integrations Visibility
- [ ] Open `Integrations` and confirm plugins are grouped into categories.
- [ ] Confirm Twitch, YouTube, OBS, and Moderation are not duplicated when duplicate native shortcuts are hidden.
- [ ] Toggle a plugin off.
- [ ] Confirm its actions/triggers disappear from automation context-menu search, categories, and integration groups.
- [ ] Confirm existing nodes from that plugin still render in existing automations.
- [ ] Toggle the plugin back on and confirm it reappears in new-node menus.
- [ ] Open a plugin details page and check Overview, Usage, Settings, Actions, Triggers, and State tabs.

## Settings And Updates
- [ ] Open `Settings` and confirm the page is not blank.
- [ ] Toggle each `Interface` preference and confirm the project sidebar updates immediately.
- [ ] Confirm interface preferences persist after closing and reopening the app.
- [ ] Open `Updates` in a development build and confirm it shows a friendly development-build state.
- [ ] In a packaged build, check latest version, release notes, check/update action, and offline failure messaging.

## Node Menu
- [ ] Search for an action inside a collapsed group and confirm it appears under `Matching Nodes`.
- [ ] Confirm category groups show data transforms, queues, overlays, OBS, chat, and utility actions.
- [ ] Use ArrowUp/ArrowDown, Enter, Escape, and Ctrl/Meta+1..4 in the context menu.
- [ ] Confirm keyboard navigation does not trigger canvas shortcuts while the menu is open.
- [ ] Right-click the canvas and add an action; confirm it appears at the click position.
- [ ] Right-click an existing node and add an action; confirm it appears at the click position, not at `(0, 0)`.
- [ ] Insert `Return`, `Break`, and `Continue` into an existing flow and confirm they do not reconnect to downstream nodes.

## Performance Smoke
- [ ] Create or open a graph with many nodes and data wires.
- [ ] Drag nodes and data wires and confirm wire rendering stays responsive.
- [ ] Confirm invalid data-wire hover feedback still appears while dragging.

## Smoke Checks
- [ ] Run `corepack yarn test`.
- [ ] Run `corepack yarn check`.
- [ ] Create a new automation, save it, close it, reopen it, and confirm graph data persists.
- [ ] Test-run a simple graph and confirm active node highlighting, result badges, and errors still appear.
