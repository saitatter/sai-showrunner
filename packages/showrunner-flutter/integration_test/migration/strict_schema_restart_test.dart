import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:showrunner_flutter/persistence/automation_repository.dart';
import 'package:showrunner_flutter/schema/automation.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('rejects legacy-shaped input without mutating canonical data', () async {
    final root = await Directory.systemTemp.createTemp(
      'showrunner-schema-integration-',
    );
    addTearDown(() => root.delete(recursive: true));
    final canonicalFile = File('${root.path}/automations/current.yaml');
    final legacyFile = File('${root.path}/automations/legacy.yaml');
    const canonical = AutomationData(
      extra: {'name': 'Canonical'},
      graph: AutomationGraph(entryNodeId: ''),
    );
    await AutomationRepository(canonicalFile).save(canonical);
    await legacyFile.parent.create(recursive: true);
    await legacyFile.writeAsString(
      jsonEncode({
        'name': 'Legacy input',
        'nodes': [
          {'id': 'old-node', 'type': 'action'},
        ],
      }),
    );

    final catalog = await AutomationRepository.loadDirectory(legacyFile.parent);
    final legacyEntry = catalog.singleWhere(
      (entry) => entry.fileName == 'legacy.yaml',
    );
    expect(legacyEntry.isValid, isFalse);
    expect(legacyEntry.error, isA<FormatException>());

    final reopened = await AutomationRepository(canonicalFile).loadStrict();
    expect(reopened?.toJson(), canonical.toJson());
    expect(await canonicalFile.exists(), isTrue);
    expect(await legacyFile.exists(), isTrue);
  });
}
