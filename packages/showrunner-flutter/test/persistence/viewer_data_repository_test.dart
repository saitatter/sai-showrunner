import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/viewer_data_repository.dart';
import 'package:showrunner_flutter/schema/viewer_data.dart';

void main() {
  late Directory directory;
  late FileViewerDataRepository repository;
  const viewer = ViewerIdentity(id: '123/with spaces', displayName: 'Viewer');

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'showrunner-viewer-data-',
    );
    repository = FileViewerDataRepository(directory);
    await repository.saveDefinitions([
      const ViewerVariableDefinition(
        name: 'points',
        type: 'Number',
        defaultValue: 5,
      ),
      const ViewerVariableDefinition(
        name: 'greeting',
        type: 'String',
        defaultValue: 'hello',
      ),
      const ViewerVariableDefinition(name: 'vip', type: 'Boolean'),
    ]);
  });

  tearDown(() => directory.delete(recursive: true));

  test('round trips definitions and preserves primitive defaults', () async {
    final definitions = await repository.loadDefinitions();

    expect(definitions.map((definition) => definition.name), [
      'points',
      'greeting',
      'vip',
    ]);
    expect(definitions.first.type, 'Number');
    expect(await repository.getDefaultViewerData(), {
      'points': 5,
      'greeting': 'hello',
      'vip': false,
    });
  });

  test('returns defaults for a missing viewer without persisting it', () async {
    final row = await repository.loadViewer('twitch', viewer);

    expect(row.persisted, isFalse);
    expect(row.values, {'points': 5, 'greeting': 'hello', 'vip': false});
    expect(
      await directory
          .list(recursive: true)
          .where((entity) => entity is File && entity.path.endsWith('.json'))
          .isEmpty,
      isTrue,
    );
  });

  test(
    'sets values with defaults for untouched variables and updates one field',
    () async {
      final first = await repository.setViewerValue(
        'twitch',
        viewer,
        'greeting',
        'welcome',
      );
      expect(first.persisted, isTrue);
      expect(first.values, {'points': 5, 'greeting': 'welcome', 'vip': false});

      final second = await repository.setViewerValue(
        'twitch',
        viewer,
        'points',
        9,
      );
      expect(second.values, {'points': 9, 'greeting': 'welcome', 'vip': false});
      expect((await repository.loadViewer('twitch', viewer)).values, {
        'points': 9,
        'greeting': 'welcome',
        'vip': false,
      });
    },
  );

  test(
    'offsets a number from its default on first write and accumulates',
    () async {
      final first = await repository.offsetViewerValue(
        'twitch',
        viewer,
        'points',
        2,
      );
      expect(first.values['points'], 7);

      final second = await repository.offsetViewerValue(
        'twitch',
        viewer,
        'points',
        -1,
      );
      expect(second.values['points'], 6);
    },
  );

  test('keeps viewer records isolated and rejects invalid offsets', () async {
    const otherViewer = ViewerIdentity(id: 'other', displayName: 'Other');
    await repository.setViewerValue('twitch', viewer, 'points', 12);

    expect(
      (await repository.loadViewer('twitch', otherViewer)).values['points'],
      5,
    );
    expect(
      () => repository.offsetViewerValue('twitch', viewer, 'greeting', 1),
      throwsA(isA<StateError>()),
    );
    expect(
      () =>
          repository.offsetViewerValue('twitch', viewer, 'points', double.nan),
      throwsA(isA<ArgumentError>()),
    );
  });
}
