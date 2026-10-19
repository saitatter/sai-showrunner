import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/spellcast/runtime.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  late Directory directory;
  late ShowRunnerDataService dataService;
  late List<(String, String, dynamic)> calls;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('showrunner-spellcast-');
    dataService = ShowRunnerDataService(directory);
    await dataService.savePluginSettings('twitch', {
      'accessToken': 'token',
      'broadcasterId': 'channel-1',
    });
    calls = [];
  });

  tearDown(() => directory.delete(recursive: true));

  test('loads and parses the remote spell catalog', () async {
    final service = SpellcastService(
      dataService: dataService,
      request: (method, path, query, body) async {
        calls.add((method, path, body));
        return [
          {
            '_id': 'remote-1',
            'name': 'Raid',
            'description': 'Welcome',
            'bits': 100,
            'color': '#719ece',
            'enabled': true,
          },
          {'name': 'invalid'},
        ];
      },
    );

    final spells = await service.listSpells();

    expect(spells.single.id, 'remote-1');
    expect(spells.single.enabled, isTrue);
    expect(calls.single.$1, 'GET');
    expect(calls.single.$2, '/streams/channel-1/buttons/');
  });

  test('maps create, update, and delete to the Spellcast API', () async {
    final service = SpellcastService(
      dataService: dataService,
      request: (method, path, query, body) async {
        calls.add((method, path, body));
        if (method == 'DELETE') return null;
        return {
          '_id': 'remote-2',
          'name': body['name'] ?? 'Raid',
          'description': body['description'] ?? '',
          'bits': body['bits'] ?? 10,
          'color': body['color'] ?? '#719ece',
          'enabled': body['enabled'] ?? false,
        };
      },
    );

    final created = await service.createSpell(
      name: 'Raid',
      description: 'Welcome',
      bits: 50,
      color: '#CC3F9A',
      enabled: true,
    );
    final updated = await service.updateSpell('remote-2', enabled: false);
    await service.deleteSpell('remote-2');

    expect(created.id, 'remote-2');
    expect(updated.enabled, isFalse);
    expect(calls.map((call) => call.$1), ['POST', 'PUT', 'DELETE']);
    expect(calls[1].$2, '/streams/channel-1/buttons/remote-2');
    expect(calls[1].$3, {'enabled': false});
  });

  test('requires Twitch credentials before remote calls', () async {
    final emptyDirectory = await Directory.systemTemp.createTemp(
      'showrunner-spellcast-empty-',
    );
    addTearDown(() => emptyDirectory.delete(recursive: true));
    final service = SpellcastService(
      dataService: ShowRunnerDataService(emptyDirectory),
      request: (_, _, _, _) async => <dynamic>[],
    );

    expect(service.listSpells, throwsA(isA<StateError>()));
  });
}
