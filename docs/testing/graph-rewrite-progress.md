# Graph rewrite started — 2026-10-16

The requested plan from Downloads has been copied unchanged to the local
`sai_nodes` repository at `docs/greenfield-plan.md`. Implementation is on the
local branch `rewrite/graph-1.0` in `C:/Users/saita/Desktop/repos/sai_nodes`.
Detailed phase tracking lives in that repository's `docs/greenfield-progress.md`.

Phase A is implemented: two workspace packages, pure Dart geometry, deeply
immutable graph documents, unified connections, explicit presentations,
new-format serialization, rebuildable/incremental indexes, stable semantic type
IDs, and structural diagnostics which retain invalid entities.

Verification: 11 core tests and 75 Flutter canvas tests passed; formatting and
workspace analysis passed. The core also resolves, analyzes and passes its tests
in a standalone temporary package without Flutter. Phase B, declarative node
definitions and bounded dynamic resolution, is next.

The current Showrunner dependency, runtime and saved documents are unchanged.
This is the foundation milestone, not the completed graph editor replacement.
There are no compatibility adapters or old-document migration helpers. The
existing canvas was moved into its package and will be replaced during the
controller/scene phases; Showrunner domain cutover follows Phase H onward.

Before starting, the remaining audit changes in Showrunner were reviewed and
committed in three groups: workspace/dependency cleanup, CI and verification
tools, and audit/UI evidence. `.gitignore` now also excludes local
`pubspec_overrides.yaml` files. The immutable Yarn install, TypeScript checks,
98 JavaScript tests, parity gates and real browser smoke passed.

Portable OBS, local integration credentials and generated proof artifacts remain
local and ignored; no personal OBS profile was modified or deleted.
