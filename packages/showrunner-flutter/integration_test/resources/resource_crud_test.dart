import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/schema/resource.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('creates, reads, updates, lists, and deletes a resource', () async {
    final root = await Directory.systemTemp.createTemp(
      'showrunner-resource-integration-',
    );
    addTearDown(() => root.delete(recursive: true));
    final repository = ResourceRepository(
      Directory('${root.path}/overlays'),
      resourceType: 'Overlay',
    );
    const initial = ResourceData(
      id: 'demo-overlay',
      config: {
        'name': 'Demo overlay',
        'width': 1920,
        'height': 1080,
        'widgets': <dynamic>[],
      },
    );
    await repository.save(initial);

    expect((await repository.load('demo-overlay'))?.toJson(), initial.toJson());
    expect((await repository.list()).map((resource) => resource.id), [
      'demo-overlay',
    ]);

    const updated = ResourceData(
      id: 'demo-overlay',
      config: {
        'name': 'Updated overlay',
        'width': 1280,
        'height': 720,
        'widgets': [
          {'id': 'title', 'type': 'text'},
        ],
      },
      state: {'healthy': true},
    );
    await repository.save(updated);
    expect((await repository.load('demo-overlay'))?.toJson(), updated.toJson());

    await repository.delete('demo-overlay');
    expect(await repository.load('demo-overlay'), isNull);
    expect(await repository.list(), isEmpty);
  });
}
