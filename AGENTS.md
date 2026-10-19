# Working rules

- Follow the user's instructions over this file.
- Use conventional commit titles and a body explaining the change, reason and validation.
  Keep each commit focused; split documentation, release tooling and independent fixes.
- Add or update a short user-facing entry in the matching section of `CHANGELOG.md` under
  Unreleased in the same commit. Keep released entries intact.
- Reserve `Fixes` for problems in functionality that existed before the current
  feature work. Corrections made while implementing a new unreleased feature
  belong in that feature's `Features` entry, not in separate `Fixes` notes.
  Update the existing feature entry when needed instead of listing implementation
  iterations as release fixes.
- Release only by manually running Release on main. Do not bump versions, create
  release tags, publish a release or bypass reviews unless the session authorizes it.
  Follow [the release policy](docs/versioning-policy.md). A PR merge must not publish.
- For a PR with several independent commits, prefer rebase-and-merge so conventional
  commit intent reaches main; squash a single logical change. Preserve published history.
- Run `scripts/ci-check.ps1` before pushing. Add `-Integration` for native app/editor
  changes and `-Visual` for layout/font changes. CI uses the same required gates.
  Report failures honestly; do not weaken assertions or thresholds to obtain green CI.
- The supported SDK is Flutter 3.47.7 / Dart 3.13.5; Node is 22 and Yarn is 4.1.0.
  Use committed lockfiles. Keep CI, release, nightly and contributor instructions aligned.
- Flutter/Dart owns the desktop product. TypeScript/DOM/WebGL owns the OBS browser
  overlay. Keep browser-only rendering in that boundary and preserve its protocol.
- Use sai_nodes immutable documents, commands/history and shared scene geometry.
  Keep runtime state/traces outside authoring documents; definitions describe types,
  ports and fields, not execution callbacks.
- Do not add old-format decoders, compatibility aliases, abandoned editors or dead code.
  Reject unsupported documents visibly without overwriting them. Never reset user data.
- Never modify the user's OBS profiles, live databases, credentials or production
  resources for testing. Use isolated app storage and the workspace portable OBS
  instance on port 4456. Live writes require the user's session authorization.
- Never commit tokens, passwords, signing certificates or connections.local.yml.
  Keep logs, captures, builds and scratch work in ignored .tmp directories.
- Keep current documentation in one living file per topic. Update existing docs and
  remove superseded audits/plans; do not create dated QA logs as permanent documentation.
  Keep reusable fixtures, license notices and frozen comparison references.
- Inspect visual differences before updating baselines. Record SDK, capture contract,
  intended changes and comparison results in the testing docs. Do not replace frozen
  Electron references or raise thresholds as a substitute for correcting regressions.
- External plugins must follow ADR-003's isolated, versioned protocol direction.
  Do not load arbitrary third-party code into the desktop process.
- Search with rg before reading. Keep output focused, run targeted checks first, and
  expand verification when changes, failures or unresolved risks justify it.
