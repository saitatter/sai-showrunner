import '../../schema/automation.dart';

final class MigrationReport {
  const MigrationReport({
    required this.sourceSchemaVersion,
    required this.documentKind,
    required this.actionCount,
    this.warnings = const <String>[],
    this.backupPath,
  });

  final Object? sourceSchemaVersion;
  final String documentKind;
  final int actionCount;
  final List<String> warnings;
  final String? backupPath;

  bool get migrated => documentKind == 'legacy';

  MigrationReport withBackup(String path) => MigrationReport(
    sourceSchemaVersion: sourceSchemaVersion,
    documentKind: documentKind,
    actionCount: actionCount,
    warnings: warnings,
    backupPath: path,
  );
}

final class AutomationMigrationResult {
  const AutomationMigrationResult({
    required this.automation,
    required this.report,
  });

  final AutomationData automation;
  final MigrationReport report;

  AutomationMigrationResult withBackup(String path) =>
      AutomationMigrationResult(
        automation: automation,
        report: report.withBackup(path),
      );
}
