# Graph rewrite progress — 2026-10-16

The requested plan is copied unchanged in the sibling sai_nodes repository,
at docs/greenfield-plan.md. Its implementation branch is rewrite/graph-1.0;
Showrunner changes remain on migration/flutter. Nothing has been pushed.

## Implemented

The library now has a pure Dart immutable graph core, strict version-1 codec,
declarative definitions, dependency-tracked resolution, transactional commands,
history, clipboard, scene geometry, virtualized canvas and scoped execution
visuals. Flutter owns painting and input; Showrunner owns runtime semantics.
The library progress document records tests, performance measurements and limits.

Showrunner has a canonical AutomationDocument and typed plugin definitions.
The compiled VM and interpreter consume ephemeral projections of that document,
using the actual node/connection IDs. Subgraph signatures have stable parameter
and output IDs. Authoring state, settings and signatures share one undo history.
Runtime validation rejects invalid definitions, ports and types before actions run.
Run from a selected subgraph node carries the execution space through queue and
compiler, initializes parameter defaults and reports the correct trace scope.

Application tabs now own individual controllers, keeping history, camera and
selection across tab switches. Root graphs, profiles, stream plans, repositories,
queues and starter templates use the new document. The palette and inspector
expose plugin fields without truncation, including asynchronous resource options.
Search finds nodes across spaces; a sheet exposes the inspector in narrow views.
No legacy document decoder or migration helper has been added.

The cutover also fixed unstable IDs in missing stream-plan inline automations,
profile trigger matching by transient object identity, and numeric starter outputs
connected to text inputs without explicit conversion nodes. Save completion marks
the captured revision, preserving edits made while an asynchronous save runs.

## Verification so far

- Full Flutter unit/widget suite: 731 passed, 7 external live probes skipped.
- Two additional search/narrow-inspector widget scenarios passed afterward.
- Windows runtime integration: 5 passed, including subgraph return bindings,
  queues, profiles, action failures and cancellation.
- Windows app surface integration: 2 passed, including actual graph geometry.
- Windows debug build passed; screenshots and logs are ignored local artifacts.

Windows document integration also passed: 2 edit/save/close workflows, 1 creation
workflow, 1 reopen workflow and 1 strict-format rejection workflow.
These counts include tests of the old shader/editor implementation and therefore
are not evidence that the whole rewrite is finished.

## Remaining

Shader editor migration, host clipboard subgraph dependencies,
inline execution feedback and removal of the old editor/runtime stacks
remain. Final native regression, pure-core isolation, benchmarks, package checks
and documentation will follow their completion. Existing old implementations are
temporary during cutover and must be removed before declaring the plan complete.

Git dependencies are pinned to local commits in the sibling library. Local path
overrides are ignored; clean remote checkout requires publishing those library
commits first. Credentials, portable OBS and generated artifacts remain ignored.
The personal OBS profile is not used or modified.
