# Branch Protection

Protect `main` in GitHub repository settings with these rules:

- Require a pull request before merging.
- Require branches to be up to date before merging.
- Require conversation resolution before merging.
- Require linear history and squash merges for feature PRs.
- Restrict direct pushes to `main`.
- Require these status checks:
  - `flutter-windows`
  - `browser-overlay`
  - `release-dry-run`
- Keep releases gated by the `Release` workflow:
  - `package-windows` must build and smoke the Flutter Windows archive before
    uploading and publishing the draft release.

The release workflow intentionally creates draft GitHub releases first. The draft is only published after Windows assets are built, smoke-checked, uploaded, and verified to exclude `builder-debug.yml`.

Only the Flutter Windows archive is published for now:

- `ShowRunner-Flutter-windows-<version>.zip`

The archive is currently unsigned and there is no installer or updater metadata
asset. Do not add Linux, macOS, installer, or automatic replacement assets until
those packages and their smoke tests exist in CI.
