# Local application workflows — 2026-10-16

This round covers application workflows independently of Twitch and OBS.
All fixtures used isolated temporary data directories. No real credentials or
personal OBS settings were used.

## Bugs reproduced and fixed

### Variables

- A `viewerDataAdded` event for another person replaced the viewer currently
  being edited. New-viewer events now refresh the table without changing the
  editor's selection.
- Switching between viewers with equal persisted values retained an unsaved
  text draft from the previous viewer. Field identity now includes the viewer.
- A slow load/save could overwrite the panel after selecting another viewer.
  Results are now applied only to the selection that initiated the operation.
- Deleting the definition used for table sorting caused a dropdown assertion.
  The panel falls back to ID sorting when that definition disappears.
- Resetting/editing a session variable saved a resource but did not change its
  live value, because reloading intentionally preserves session state. Editor
  saves now explicitly apply the requested value to the variable runtime.
- Saving a variable resource converted numbers/booleans/JSON/lists to strings;
  JSON maps were displayed using Dart's non-JSON string representation. The
  editor now formats JSON and saves typed values, retains extra state fields,
  and rejects malformed input without closing the editor.
- An explicit null current value was replaced by the default when reopening.
  Resource decoding now distinguishes an absent value from an explicit null.

### Queues

- Creating a second queue selected its name but retained the first queue's
  runtime controls and contents. Creation now selects the corresponding queue
  instance as well as its row.
- Resume changed the paused flag without starting pending work. It now resumes
  through the queue manager.
- Replay enqueued another execution without starting processing. It now asks
  the manager to drain the selected queue, preserving paused queue semantics.
- Status pills now reflect runtime pause state. An empty resource list falls
  back to the default queue instead of retaining a deleted selection.

Regression tests exercise the UI controls, persisted files, delayed repository
responses and runtime execution; the default suite retains the existing queue
tests as well as the added regression workflow.

## Verified application workflows

Native Windows integration tests exercised:

- Graph document save, close, reopen, Cancel, Discard, Save and Save All.
- First-run setup directly and through the application shell.
- Named automation/profile creation.
- Production graph composition, nested subgraphs, queued execution/history,
  active-profile trigger dispatch, failures and cancellation.
- Strict schema rejection without mutating canonical files.
- Resource create/open/delete and persistence across application restart.
- Stream Plan document restoration after restart.
- Overlay label rename/edit/reorder/save/reopen. An outdated integration test
  still addressed the removed name field; it now uses inline layer rename.
- Remote dashboard discovery against an authenticated local HTTP fixture;
  this does not assert a live cloud connection.

Widget regression workflows additionally cover session-variable reset/edit,
search, restart behavior, deletion, viewer selection and delayed operations,
typed resource values, invalid JSON and independent queue controls.

## Validation

- `flutter test --reporter compact`: **728 passed**, six opt-in live tests
  skipped. Log: `packages/showrunner-flutter/.tmp/local-functional-regression-final.log`.
- `flutter analyze`: no issues.
- After the final cleared-field validation adjustment, the 27 resource-editor
  tests and analysis passed again.
- **26 distinct Windows scenarios passed**, including ten local-data control
  regressions replayed in the native engine. Two stale test-harness cases were
  corrected and passed on targeted reruns; the initial combined logs retain
  those failures for traceability.
- Formatting check: ten changed Dart files, no changes needed.
- Desktop logs are under the Flutter package's ignored `.tmp/` directory:
  `local-desktop-documents.log`, `local-desktop-queues.log`,
  `local-desktop-batch.log`, `local-desktop-resources.log`, and
  `local-desktop-variable-queue-final.log`, `local-desktop-viewer-race.log`,
  and `local-desktop-controls.log`. The permanent `local_data_controls_test.dart`
  target passed all ten cases together and is included in the desktop runner.

The first combined desktop run found the outdated overlay test. Its corrected
three-case resource suite subsequently passed independently. The first optional
native replay of the new widget regressions was interrupted while a test waited
for animations with an intentionally pending repository future. The test now
pumps bounded frames before completing that future. Native integration bindings
also disable the text-input stub by default; the two-submission race test now
registers it so actions reach the current input client after refocusing. That
case passed in the native engine after the correction.

## Repeat

From `packages/showrunner-flutter`:

```powershell
flutter test test/features/variables test/features/queue test/plugins/resources/resource_editors_test.dart
flutter test integration_test/application/document_edit_save_close_test.dart -d windows
flutter test integration_test/resources/queue_lifecycle_test.dart -d windows
flutter test integration_test/resources/local_data_controls_test.dart -d windows
flutter test integration_test/runtime/runtime_workflows_test.dart -d windows
flutter test integration_test/resources/resource_workspace_lifecycle_test.dart -d windows
```

The repository's `scripts/test-flutter-integration.ps1` runs the broader desktop
suite, including setup, creation, schema and remote fixtures.
No external keys are needed for the local workflows covered here.
