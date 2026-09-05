import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/automation_repository.dart';
import 'package:showrunner_flutter/persistence/profile_repository.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/schema/automation.dart';
import 'package:showrunner_flutter/schema/profile.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/services/project_catalog_service.dart';

void main() {
  test('loads and sorts persisted project documents by display name', () async {
    final root = await Directory.systemTemp.createTemp('showrunner-catalog-');
    addTearDown(() => root.delete(recursive: true));

    await AutomationRepository(
      File('${root.path}/automations/second.yaml'),
    ).save(const AutomationData(extra: {'name': 'Zulu'}));
    await AutomationRepository(
      File('${root.path}/automations/first.yaml'),
    ).save(const AutomationData(extra: {'name': 'Alpha'}));
    await ProfileRepository(File('${root.path}/profiles/live.yaml')).save(
      const ShowRunnerProfile(
        name: 'Live',
        activationMode: 'toggle',
        triggers: [],
        activationCondition: {},
        activationAutomation: AutomationData(),
        deactivationAutomation: AutomationData(),
      ),
    );
    await ResourceRepository(Directory('${root.path}/dashboards')).save(
      const ResourceData(id: 'dashboard', config: {'name': 'Main dashboard'}),
    );
    await ResourceRepository(
      Directory('${root.path}/sound/splitters'),
    ).save(const ResourceData(id: 'splitter', config: {'name': 'Headphones'}));

    final fixtureCatalog = await ShowRunnerProjectCatalogService(root).load();
    expect(
      fixtureCatalog.automations.map(
        (entry) => entry.automation!.extra['name'],
      ),
      ['Alpha', 'Zulu'],
    );
    expect(fixtureCatalog.profiles.single.profile!.name, 'Live');
    expect(
      fixtureCatalog.resources['Dashboard']!.single.title,
      'Main dashboard',
    );
    expect(
      fixtureCatalog.resources['AudioSplitterOutput']!.single.title,
      'Headphones',
    );
  });
}
