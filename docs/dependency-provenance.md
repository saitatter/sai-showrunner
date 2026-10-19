# Dependency and license provenance

The repository license is [AGPL-3.0](../LICENSE.md). Existing CastMate author
and copyright notices are retained. The frozen Electron/Vue reference is a
comparison artifact; it is not included in the maintained application workspaces.

The `ISC` declarations in the maintained schema and plugin package manifests
were already present in the frozen reference checkout. This cleanup preserves
those declarations rather than guessing a new license for contributed code.
These package metadata declarations do not replace the repository license.
Any publication of these packages should resolve that inherited discrepancy
against contributor records first. No standalone package publication is added here.

Font notices remain under `packages/showrunner-flutter/assets/fonts/`.
The `sai_nodes` dependency remains a separately licensed upstream dependency.
The browser overlay, parity reference fixtures and interpreter oracle remain
because they serve active runtime and verification purposes.

Node.js is 22 across `.nvmrc`, CI and contributor instructions. Yarn is managed
by the root `packageManager` declaration. Maintained workspaces use actual
TypeScript checks; the unused WebSocket RPC workspace and obsolete Electron
launch scaffolding have been removed. Wildcard tooling dependencies are pinned
to the versions already resolved by the lockfile.
