# Windows release regression checklist

Use this before a Windows release after graph editor, queue, integration,
overlay, or starter changes.

## Automation and profiles

- [ ] Create an automation from each available starter and confirm every graph
      has a valid entry node.
- [ ] Save, close, reopen, and execute a graph containing actions, conditions,
      data wires, variables, queues, and a subgraph call.
- [ ] Add a profile trigger, configure its event and filter, save, activate the
      profile, and confirm its V2 trigger automation executes once.
- [ ] Confirm an invalid non-V2 document is reported and is not rewritten.

## Integrations

- [ ] Open Integrations and confirm plugins are grouped without duplicates.
- [ ] Toggle a plugin off and confirm its new-node entries disappear while
      existing nodes remain inspectable.
- [ ] Check Twitch, YouTube, OBS, Moderation, remote, sound, input, and lighting
      connection or health surfaces relevant to the release.

## Editor interaction

- [ ] Connect compatible control and data ports and confirm invalid links are
      rejected with visible feedback.
- [ ] Add, move, duplicate, delete, copy, cut, paste, fit, and search nodes.
- [ ] Confirm Return, Break, and Continue nodes preserve their control flow.
- [ ] Confirm missing plugin nodes remain visible and diagnosable.

## Overlays and updates

- [ ] Open an overlay resource, add a widget, save it, and verify the persisted
      widget configuration.
- [ ] Load the browser source in OBS and confirm the presence indicator and RPC
      connection.
- [ ] Check the update page in a development build and in a packaged build,
      including offline error handling.

## Commands

```powershell
Push-Location packages/showrunner-flutter
flutter analyze
flutter test
flutter build windows --release
Pop-Location
.\scripts\smoke-flutter-windows.ps1 -Configuration Release
.\scripts\package-flutter-windows.ps1 -Version <version>
```
