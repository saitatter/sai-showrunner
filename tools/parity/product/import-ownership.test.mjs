import {describe, expect, it} from 'vitest';
import {databaseImportViolations} from './import-ownership.mjs';

describe('desktop database ownership', () => {
  it('rejects direct database access and re-exports in presentation and provider code', () => {
    expect(databaseImportViolations('lib/features/variables/panel.dart',"import 'package:sqlite_async/sqlite_async.dart';")).toHaveLength(1);
    expect(databaseImportViolations('lib/plugins/twitch/store.dart','export "package:sqlite3/sqlite3.dart";')).toHaveLength(1);
    expect(databaseImportViolations('lib/persistence_ui/store.dart',"import\n 'package:sqlite3/sqlite3.dart';")).toHaveLength(1);
  });
  it('permits the owned persistence layer and isolated verification tools', () => {
    for (const path of ['lib/persistence/sqlite_viewer_data_repository.dart','lib\\persistence\\viewer_store\\database.dart','test/persistence/sqlite_test.dart','tool/viewer_data_benchmark.dart']) {
      expect(databaseImportViolations(path,"import 'package:sqlite3/sqlite3.dart';")).toEqual([]);
    }
    expect(databaseImportViolations('lib/features/variables/panel.dart',"import '../../persistence/viewer_data_repository.dart';\n// import 'package:sqlite3/sqlite3.dart';")).toEqual([]);
  });
});
