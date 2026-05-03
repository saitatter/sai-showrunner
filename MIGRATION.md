# Migration Guide: v1.0.0 Beta

ShowRunner v1.0 beta moves automations to the graph-only runtime.

## What Changes

- Automations persist as `schemaVersion: 2`.
- `graph`, `subgraphs`, `dataWires`, and `variableNodes` are the canonical automation data.
- Legacy `sequence` and `floatingSequences` fields are removed from saved automation, profile, and stream-plan files after load.
- Runtime execution uses `GraphCompiler` and `GraphVM`; the old sequence runner is no longer used.

## Automatic Migration

On load, ShowRunner normalizes:

- standalone automation resources;
- profile trigger/activation/deactivation automations;
- stream-plan activation/deactivation and segment automations.

If a legacy automation has actions in `sequence.actions` and no graph yet, ShowRunner creates a simple left-to-right graph before saving the upgraded file.

## What To Check After Updating

1. Open each important automation.
2. Confirm the graph opens without the recovery panel.
3. Select overlay actions and re-check target widgets if a widget was renamed.
4. Test-run the automation and watch the execution path.
5. For queue-driven alerts, confirm the queue worker starts and completes.

## Known Beta Limitations

- Subgraph editing has parameter/output metadata and call-node ports, but deeper nested graph navigation will continue to improve during the beta.
- Starter templates leave overlay widget targets empty by design; select the target widget after creating the starter.
- Windows is the only packaged release target during the current beta line.

## Backup Advice

Before testing the beta on an existing production setup, copy the ShowRunner project/data directory. The migration saves normalized files back to disk once they load successfully.

## For Developers

Do not reintroduce `sequence` or `floatingSequences` into public schema. If a compatibility bridge is needed, keep it inside migration/normalization code and strip stale fields before persistence.
