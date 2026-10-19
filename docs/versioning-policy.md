# Versioning and releases

## One manual workflow

Run **Release** from GitHub Actions on **main**. Pushes and PR merges run CI only;
they never tag, change versions or publish. The current package version is a source
baseline, not evidence that the Flutter cutover is already released.

| Input | Behavior |
| --- | --- |
| version (empty) | Pick MAJOR for breaking commits, MINOR for feat, PATCH for fix/perf since the last reachable stable tag |
| version | Explicit X.Y.Z or X.Y.Z-beta.N, without v or build metadata |
| dry_run | Preview version and Unreleased notes only; no commits, tags or releases, and no signing credentials needed |
| backfill_version | Validate and rebuild Windows assets from an existing immutable Flutter tag; preserve release/prerelease/latest state |

Docs, CI, refactor, build and chore commits alone do not automatically release.
An explicit version can release maintenance work. A release must advance reachable
published versions, include meaningful Unreleased notes and keep root package,
Flutter pubspec and updater fallback versions aligned. The Flutter build number
increments independently. No tag is moved or replaced.

Local preview:

```powershell
node tools/release/prepare.mjs --check
node tools/release/prepare.mjs --check --version 2.0.0-beta.1
```

The workflow previews first, runs the same reusable CI gates on the frozen commit,
then prepares and atomically pushes a version/changelog commit and annotated tag.
It updates package.json, Flutter pubspec, updater fallback and CHANGELOG.md together.
If main advanced during validation, publication stops rather than releasing an
untested new snapshot. The notes come from Unreleased, with a full comparison link.

The GitHub release starts as a **draft**. Windows packaging checks the bundled
YouTube client, builds the browser overlay, validates the unsigned bundle, and runs
isolated application and updater install/rollback smokes. Only a successful asset
upload publishes it. Prereleases are never marked Latest. Stable releases become
Latest only after the package is present. A failed build leaves a draft for
inspection; it does not publish an incomplete release. Windows packages are
deliberately distributed without an Authenticode signature.

Backfill never rewrites tags, bumps versions or changes an existing release's
publication state. It rejects the old Electron tags and mismatched version files.
Rebuilding an existing asset is explicit and replaces that asset only after a new
validated package has passed. A draft remains a draft during backfill; publishing a
recovered draft is a separate explicit operator action.

## Repository configuration

Set these as repository secrets, or release-environment secrets where applicable:

- RELEASE_TOKEN: a narrowly scoped token allowed to push the version commit/tag to
  protected main (Contents read/write plus the repository's allowed review bypass).
- SHOWRUNNER_YOUTUBE_CLIENT_SECRET: optional companion to the bundled OAuth client.

Set SHOWRUNNER_YOUTUBE_CLIENT_ID as a repository variable.
The environment named `release` may impose approvals; workflow code must not bypass
those rules. Do not expose signing/release credentials to pull-request jobs.

Preview and PR CI do not need publishing credentials. A new release requires
RELEASE_TOKEN, but neither public packaging nor proof requires signing secrets.
`Windows release proof` runs manually on trusted main and uploads an unsigned
test archive without creating a GitHub release. Both workflows run application
and updater install/rollback smokes. The optional local signing helper and its
isolated self-signed CI fixture remain separately tested; public artifacts never
use that test certificate.

## Contribution and merge policy

Keep concise user-facing entries under Features, Fixes, Refactors, Docs or CI & Build
in CHANGELOG.md's Unreleased section. Keep published sections intact. Conventional
commits select the version; curated changelog entries describe the user impact.
Prefer rebase-and-merge for independent commits, or a meaningful conventional
squash title for a single logical change. Do not hide breaking changes in a generic
merge title. Never reset user data to make a schema change or upgrade pass.

Only Windows ZIP assets are currently supported. Do not copy Colectarr's Linux,
Android, macOS or container release jobs until ShowRunner supports those products.
