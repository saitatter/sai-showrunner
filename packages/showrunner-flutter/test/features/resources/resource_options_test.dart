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
}
