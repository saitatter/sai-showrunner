# Viewer Data

The desktop stores Viewer Data in `viewer-data/viewers.sqlite`, one database per
application data directory. Portable installations keep their own database.
`ViewerDataRepository` remains the provider/UI/overlay boundary; its production
adapter is `SqliteViewerDataRepository`. The in-memory adapter supports tests.

## Ownership and schema

`sqlite_async` runs database work on background isolates. Canonical-path handles
share one reference-counted pool in a process, with two readers and one writer.
SQLite serializes writers across processes. Connections enable foreign keys and
a 15-second busy timeout. The store enables WAL after validating its application
identity and version, and uses FULL synchronous durability. Application shutdown
stops provider/event workers before draining and closing the database. Embedded
plugin hosts and standalone variable workspaces close the handles they own.

SQL query profiling is explicitly disabled, including in debug/profile builds,
so bound viewer values are not copied into DevTools timeline events. Benchmarks
use explicit Stopwatch timing.

Schema version 1 uses `PRAGMA user_version` and application ID `SVWD`:

- `viewers`: provider-qualified ID, display name and normalized sort keys.
- `viewer_variable_definitions`: ordered definitions, defaults and typed sort data.
- `viewer_values`: typed values keyed by provider, viewer ID and variable name.
  Numbers use SQLite integer/real storage, booleans and null remain distinct,
  and complex values retain JSON representations. A compound index supports
  provider/variable/rank/value/identity ordering.
- `viewer_store_metadata`: completion marker for the one-time file import.

Reads of an unknown viewer return defaults without inserting a viewer. Creating
or writing a viewer freezes its current defaults, matching the file store's
behavior. A subsequently added field remains default-derived until that viewer
is written. Explicit null remains null; numeric offsets treat it as zero.
Definition edits validate existing explicit values and compare revisions inside
the same transaction. Incompatible types and stale edits fail without replacing data.
Values for removed/unknown definitions remain stored and survive interchange;
ordinary queries project the currently declared definitions.

Queries select and paginate in SQL, then hydrate only the selected page. Numeric
leaderboards select their index page before joining viewer identities, avoiding
identity reads for skipped rows. Ascending order is null, number, boolean, string,
then complex JSON; descending reverses that order. Text uses persisted lowercase
keys. Ties use normalized ID then exact ID; an unavailable sort variable falls
back to ID. `start`/`end` retain the existing offset-page contract. Deep offsets
still traverse index entries; this is not keyset pagination.

## Importing existing installations

On first initialization, one transaction imports the current `variables.yaml` and
provider-qualified base64url-named JSON rows. Close older application instances
before the first run of this version. Source files remain untouched. A committed
completion marker prevents subsequent imports or fallback reads of those files.
The small immutable `viewers.sqlite-owner` sidecar records that this directory
has an initialized database. If that database disappears, opening the store fails
instead of reimporting stale JSON or starting over; restore a verified backup.
Keep the originals until the resulting database has been checked and backed up.

Malformed definitions/rows, linked provider rows and filename/identity mismatches
stop the import with payload-free diagnostics. Imported rows and definitions roll
back together. After repairing the source, restart to retry the pending import.
An unsupported database version, an unrelated database or corruption fails
visibly; the store never resets it or substitutes an empty file catalog.

## Backup and portable interchange

Run these commands from `packages/showrunner-flutter` with the supported SDK:

```powershell
dart run tool/viewer_data.dart backup <viewer-data-directory> <new-backup.sqlite>
dart run tool/viewer_data.dart export <viewer-data-directory> <new-export.ndjson>
dart run tool/viewer_data.dart import <viewer-data-directory> <export.ndjson>
# Deliberately replace conflicting definitions and existing viewer rows:
dart run tool/viewer_data.dart import <viewer-data-directory> <export.ndjson> --overwrite
```

Backup uses `VACUUM INTO` to snapshot committed WAL contents while the store is
open. Copying just the main SQLite file is not an online backup. Backup/export
targets must not exist. Retain successful backups separately from the live store.
The CLI closes its pool before exiting and reports errors without printing rows.

The versioned NDJSON archive contains definitions, provider-qualified rows and a
completion/count footer. Export holds a consistent read snapshot and streams
pages. Import is one write transaction; incomplete archives, duplicate identities
or conflicting definitions are rejected. Default import preserves existing rows;
`--overwrite` explicitly merges incoming values and updates their identity.
Type changes must remain compatible with other stored values; overwrite does not
bypass schema validation.
Archives preserve resolved values and hidden fields; SQLite backup also preserves
internal default-derived state. Configuration documents and encrypted credentials
remain under their existing repositories; they are not moved into this database.

## Verification and measurements

`test/persistence/sqlite_viewer_data_test.dart` verifies one-time import, rollback,
safe retries, untouched unsupported/corrupt databases, defaults/null, stable typed
pagination, index use, independent handles, archive truncation and live WAL backup.
Its bundled process fixture verifies concurrent independent writers and abrupt
exits before/after commit. The shared store contract, synchronizer drain, registry
teardown and variable workspace tests exercise the existing application boundaries.

Run `dart run tool/viewer_data_benchmark.dart` for 1K/10K/100K generated viewers,
or pass explicit sizes. It uses isolated workspace `.tmp` storage, 30 timed samples
after warmup and verifies 100 concurrent increments plus index selection. It does
not read or modify the installed application's data. The process fixture is built
once as a native CLI bundle, so concurrent workers do not rebuild loaded Windows DLLs.

Local Windows measurements with Flutter 3.47.7 / Dart 3.13.5, `sqlite_async` 0.14.8
and `sqlite3` 3.5.2, warm cache, two declared fields:

| Viewers | Archive import | First 100 median / p95 | Last 100 median / p95 | ID lookup median | Increment median |
| --- | --- | --- | --- | --- | --- |
| 1,000 | 496 ms | 3.44 / 5.71 ms | 3.02 / 5.18 ms | 0.83 ms | 1.68 ms |
| 10,000 | 2,022 ms | 3.52 / 4.49 ms | 3.44 / 4.17 ms | 1.26 ms | 1.77 ms |
| 100,000 | 22,191 ms | 3.25 / 4.30 ms | 9.26 / 10.57 ms | 1.10 ms | 2.56 ms |

These are local measurements, not CI thresholds or a JSON comparison. Initial
JSON file migration additionally pays filesystem enumeration/read costs and is
not represented by the archive-import timing. Every benchmark database is disposable.
