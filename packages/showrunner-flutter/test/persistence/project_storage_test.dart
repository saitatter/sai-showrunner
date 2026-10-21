import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/persistence_issue.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/services/project_catalog_service.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';
import 'package:showrunner_flutter/schema/identifiers.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/graph/domain/automation_document.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('showrunner-owned-storage-');
  });
  tearDown(() => root.delete(recursive: true));

  Future<Directory> redirect(String segment) async {
    final app = await Directory('${root.path}/app').create();
    final outside = await Directory('${root.path}/outside').create();
    final path = '${app.path}/$segment';
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-Command',
      "New-Item -ItemType Junction -Path '${path.replaceAll("'", "''")}' -Target '${outside.path.replaceAll("'", "''")}' | Out-Null",
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    return outside;
  }

  test(
    'nested resource root redirects cannot redefine the application boundary',
    () async {
      final outside = await redirect('overlays');
      final marker = File('${outside.path}/scene.json');
      const source = '{"id":"scene","config":{"name":"Outside"}}';
      await marker.writeAsString(source);
      final repository = ShowRunnerDataService(
        Directory('${root.path}/app'),
      ).storage.resource(const ResourceTypeId('Overlay'));
      await expectLater(repository.load('scene'), throwsArgumentError);
      await expectLater(
        repository.save(
          const ResourceData(id: 'scene', config: {'name': 'Replacement'}),
        ),
        throwsArgumentError,
      );
      await expectLater(repository.delete('scene'), throwsArgumentError);
      expect(await marker.readAsString(), source);
      expect(await Directory('${outside.path}/.locks').exists(), isFalse);
    },
    skip: !Platform.isWindows,
  );

  for (final segment in ['settings', 'secrets']) {
    test(
      '$segment redirects cannot disclose or replace external credentials',
      () async {
        final outside = await redirect(segment);
        final marker = File('${outside.path}/obs.yaml');
        await marker.writeAsString('outside-marker');
        final service = ShowRunnerDataService(Directory('${root.path}/app'));
        await expectLater(
          service.loadPluginSettings('obs'),
          throwsArgumentError,
        );
        await expectLater(
          service.savePluginSettings('obs', {'password': 'replacement'}),
          throwsArgumentError,
        );
        expect(await marker.readAsString(), 'outside-marker');
      },
      skip: !Platform.isWindows,
    );
  }

  test(
    'profile roots and typed enumeration stay anchored through nested redirects',
    () async {
      final outside = await redirect('profiles');
      await File(
        '${outside.path}/profile.yaml',
      ).writeAsString('outside-marker');
      final storage = ShowRunnerDataService(
        Directory('${root.path}/app'),
      ).storage;
      await expectLater(
        storage.profile('profile.yaml').load(),
        throwsArgumentError,
      );
      await expectLater(storage.listProfiles(), throwsArgumentError);
      await expectLater(storage.listFiles('profiles'), throwsArgumentError);
      expect(
        await File('${outside.path}/profile.yaml').readAsString(),
        'outside-marker',
      );
    },
    skip: !Platform.isWindows,
  );

  test(
    'one unreadable resource scope does not discard the healthy catalog',
    () async {
      final storage = ShowRunnerDataService(root).storage;
      await storage
          .automation('healthy.yaml')
          .save(AutomationDocument.empty().withMetadata({'name': 'Healthy'}));
      await File('${root.path}/overlays').writeAsString('directory-collision');
      final catalog = await ShowRunnerProjectCatalogService(root).load();
      expect(
        catalog.automations.single.automation!.metadata['name'],
        'Healthy',
      );
      expect(catalog.resources['Overlay'], isEmpty);
      expect(catalog.issues.single.owner, 'Overlay');
      expect(catalog.issues.single.kind, PersistenceIssueKind.io);
      expect(
        await File('${root.path}/overlays').readAsString(),
        'directory-collision',
      );
    },
  );

  test(
    'resource parse errors exclude source text and malformed names remain unreadable',
    () async {
      final directory = await Directory('${root.path}/resources').create();
      await File(
        '${directory.path}/broken.json',
      ).writeAsString('{ private-marker');
      await File(
        '${directory.path}/name.json',
      ).writeAsString('{"id":"name","config":{"name":5}}');
      final entries = await ResourceRepository(directory).listWithErrors();
      expect(entries, hasLength(2));
      for (final entry in entries) {
        expect(entry.isValid, isFalse);
        expect(entry.error.toString(), isNot(contains('private-marker')));
      }
    },
  );
}
