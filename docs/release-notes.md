# Release notes

ShowRunner follows the editorial structure used by
[Collectarr](https://github.com/saitatter/collectarr-app) and
[PyLrcGet](https://github.com/saitatter/pylrcget): a banner and short summary,
then complete commit credits, new contributors and a comparison link. The artwork
and implementation belong to ShowRunner; no external rendering service is required.
The [release policy](versioning-policy.md) owns version selection and publication.

## Editorial source

Edit `Unreleased.summary` in [release-summaries.json](release-summaries.json) as
features become ready. Use short, single-line statements about observable behavior.
Keep fixes to shipped behavior separate from implementation iterations in CHANGELOG.md.
Do not claim performance improvements without measurements and linked evidence.

Release preparation freezes the summary under its automatically selected tag,
records `previousTag`, and clears Unreleased in the same commit as version files
and the changelog. Existing per-tag summaries remain intact. If a summary is
missing, the formatter takes up to ten entries from the first changelog group.
For an older release, add an explicit per-tag summary before regenerating notes.
Optional `highlights` contains up to six single-line labels of at most 48 characters
for the monitor in the banner. Release preparation freezes these alongside the
full summary; the Markdown retains the full editorial statements.

## Description layout

1. A ShowRunner banner, labeled with the tag and original release date.
2. **Changes since last release:** the editorial bullets.
3. A separator and **What's Changed**, listing non-merge commits oldest first,
   with title, author, commit link and explicitly closed issue credits from associated PRs.
4. GitHub-generated **New Contributors**, when present, and **Full Changelog**.

Commit comparisons are paginated and duplicate SHAs are removed. Metadata errors
fail the operation instead of silently dropping credits. If the complete history
would exceed the description budget, a visible comparison link replaces only the
overflow; the summary and contributor credits remain. GitHub's comparison remains
the authoritative complete history.

The banner combines an original streaming-studio illustration with deterministic
SVG text generated using Node's standard library. The built-in image generation
tool produced [the reusable JPEG background](branding/release-banner/studio.jpg)
from [this prompt](branding/release-banner/prompt.txt); the reference artwork was
used for visual direction, not copied into the asset. Regeneration needs no AI,
browser, Pillow or image service: the SVG embeds the committed JPEG and overlays
the tag, original publication date, six highlights, previous tag, commit count,
distinct merged PR count and contributor identities from the actual commit range.
The first release includes inherited upstream history; merge commits are excluded.
Issue metadata is queried once per unique PR, keeping large historical ranges
within practical API budgets. At most four identities appear on the card, with
an explicit remainder count; the Markdown credits the full history.
Published banners live on the separate `release-banners` branch. Image URLs pin the
banner commit SHA, so later updates do not change older descriptions. Never force
push or delete this history. Banner writes do not commit to main.

## Preview and update

With `gh` authenticated for this repository, preview the latest published release:

```powershell
node tools/release/notes.mjs
node tools/release/notes.mjs --tag v2.1.0 --refresh-banner
```

Preview prints Markdown and writes a local SVG under `.tmp/release-notes`; it does
not mutate GitHub. Inspect the image and Markdown before writing.
`--write` changes only the selected release's body and any newly generated banner.
`--refresh-banner` explicitly regenerates the banner; otherwise an existing banner
URL is preserved. `--all` selects all published releases and cannot accompany `--tag`.
Use it only when a deliberate historical reformat is needed.

The manual **Release notes** Actions workflow runs on main. It defaults to preview,
uploads the Markdown/SVG artifacts, and accepts a tag, write and refresh-banner
inputs. It excludes drafts and never creates tags, changes versions, uploads app
packages or changes publication state.

The separate **Release** workflow formats its explicit draft after every required
package proof and asset upload, immediately before publication. Its internal
`--include-draft --tag ... --write` path updates the body without publishing it;
only Release's final existing publication step publishes. Asset backfills preserve
existing notes and release state. Merging a PR runs neither publication workflow.
