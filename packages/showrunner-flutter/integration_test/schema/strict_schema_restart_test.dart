import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:showrunner_flutter/persistence/automation_repository.dart';
import 'package:showrunner_flutter/schema/automation.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('rejects unsupported input without mutating canonical data', () async {
    final root = await Directory.systemTemp.createTemp(
      'showrunner-schema-integration-',
    );
    addTearDown(() => root.delete(recursive: true));
    final canonicalFile = File('${root.path}/automations/current.yaml');
    final unsupportedFile = File('${root.path}/automations/unsupported.yaml');
    const canonical = AutomationData(
      extra: {'name': 'Canonical'},
      graph: AutomationGraph(entryNodeId: ''),
    );
    await AutomationRepository(canonicalFile).save(canonical);
    await unsupportedFile.parent.create(recursive: true);
    await unsupportedFile.writeAsString(
      jsonEncode({
        'name': 'Unsupported input',
        'nodes': [
          {'id': 'old-node', 'type': 'action'},
        ],
      }),
    );

    final catalog = await AutomationRepository.loadDirectory(
      unsupportedFile.parent,
    );
    final unsupportedEntry = catalog.singleWhere(
      (entry) => entry.fileName == 'unsupported.yaml',
    );
    expect(unsupportedEntry.isValid, isFalse);
    expect(unsupportedEntry.error, isA<FormatException>());

    final reopened = await AutomationRepository(canonicalFile).loadStrict();
    expect(reopened?.toJson(), canonical.toJson());
    expect(await canonicalFile.exists(), isTrue);
    expect(await unsupportedFile.exists(), isTrue);
  });
}
