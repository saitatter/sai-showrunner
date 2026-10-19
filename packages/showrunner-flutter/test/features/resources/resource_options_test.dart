import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/resources/resource_options.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  test('merges virtual sound outputs with persisted splitters', () async {
    final directory = await Directory.systemTemp.createTemp(
      'resource-options-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final splitterDirectory = Directory('${directory.path}/sound/splitters');
    final repository = ResourceRepository(splitterDirectory);
    await repository.save(
      const ResourceData(
        id: 'stream-audio',
        config: {'name': 'Stream audio', 'redirects': []},
      ),
    );

    final options = await loadResourceOptions(
      ShowRunnerDataService(directory),
      'SoundOutput',
    );

    expect(options, containsAll(['system.default', 'system.communications']));
    expect(options, contains('stream-audio'));
  });

  test('loads persisted IDs for registered resource types', () async {
    final directory = await Directory.systemTemp.createTemp(
      'resource-options-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final repository = ResourceRepository(
      Directory('${directory.path}/twitch/groups'),
    );
    await repository.save(
      const ResourceData(id: 'vip-group', config: {'name': 'VIPs'}),
    );

    final options = await loadResourceOptions(
      ShowRunnerDataService(directory),
      'CustomTwitchViewerGroup',
    );

    expect(options, ['vip-group']);
  });

  test(
    'loads automation, queue, and profile IDs for graph resources',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'workflow-resource-options-',
      );
      addTearDown(() => directory.delete(recursive: true));
      await Directory('${directory.path}/automations').create(recursive: true);
      await Directory('${directory.path}/queues').create(recursive: true);
      await Directory('${directory.path}/profiles').create(recursive: true);
      await File(
        '${directory.path}/automations/worker.yaml',
      ).writeAsString('{}');
      await File('${directory.path}/queues/alerts.yaml').writeAsString('{}');
      await File('${directory.path}/profiles/live.yaml').writeAsString('{}');

      final dataService = ShowRunnerDataService(directory);
      expect(await loadResourceOptions(dataService, 'Automation'), ['worker']);
      expect(await loadResourceOptions(dataService, 'ActionQueue'), ['alerts']);
      expect(await loadResourceOptions(dataService, 'Profile'), ['live']);
    },
  );

  test(
    'uses the canonical directories for remote IoT resource slots',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'remote-resource-options-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final lightRepository = ResourceRepository(
        Directory('${directory.path}/iot/lights'),
      );
      final plugRepository = ResourceRepository(
        Directory('${directory.path}/iot/plugs'),
      );
      await lightRepository.save(
        const ResourceData(id: 'key-light', config: {'name': 'Key Light'}),
      );
      await plugRepository.save(
        const ResourceData(id: 'desk-plug', config: {'name': 'Desk Plug'}),
      );

      final dataService = ShowRunnerDataService(directory);
      expect(await loadResourceOptions(dataService, 'Light'), ['key-light']);
      expect(await loadResourceOptions(dataService, 'Plug'), ['desk-plug']);
    },
  );
}
