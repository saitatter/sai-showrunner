import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/plugins/obs/actions.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/services/provider_settings_validator.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  test('persists OBS resources in the plugin directory', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-resources-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final repository = ResourceRepository(
      Directory('${directory.path}/obs/connections'),
    );
    const resource = ResourceData(
      id: 'obs-local',
      config: {
        'name': 'Local OBS',
        'host': '127.0.0.1',
        'port': 4455,
        'local': true,
      },
    );

    await repository.save(resource);

    expect((await repository.load('obs-local'))?.config['port'], 4455);
  });

  test('routes OBS actions through the plugin transport', () async {
    final requests = <String>[];
    final transport = CallbackObsTransport((request, data) async {
      requests.add(request);
      if (request == 'GetInputMute') return {'inputMuted': false};
      if (request == 'GetSceneItemEnabled') return {'sceneItemEnabled': false};
      if (request == 'GetSourceFilter') return {'filterEnabled': true};
      return {};
    });
    final registry = DartPluginRegistry()..register(createObsPlugin(transport));

    await registry.invokeAction('obs', 'streamStartStop', {'streaming': true});
    await registry.invokeAction('obs', 'mute', {
      'source': 'Mic',
      'muted': 'toggle',
    });
    await registry.invokeAction('obs', 'browserUrl', {
      'source': 'ChatOverlay',
      'url': 'http://127.0.0.1:3000/overlay',
    });

    expect(requests, [
      'StartStream',
      'GetInputMute',
      'SetInputMute',
      'SetInputSettings',
    ]);
  });

  test('tracks the previous OBS scene', () async {
    final requests = <String>[];
    final transport = CallbackObsTransport((request, data) async {
      requests.add(request);
      if (request == 'GetCurrentProgramScene') {
        return {'currentProgramSceneName': 'Intro'};
      }
      return {};
    });
    final registry = DartPluginRegistry()..register(createObsPlugin(transport));

    await registry.invokeAction('obs', 'scene', {'scene': 'Main'});
    final result =
        await registry.invokeAction('obs', 'prevScene', {})
            as Map<String, dynamic>?;

    expect(result?['scene'], 'Intro');
    expect(requests, [
      'GetCurrentProgramScene',
      'SetCurrentProgramScene',
      'SetCurrentProgramScene',
    ]);
  });

  test('checks OBS health through the transport', () async {
    final requests = <String>[];
    final registry = DartPluginRegistry()
      ..register(
        createObsPlugin(
          CallbackObsTransport((request, data) async {
            requests.add(request);
            return {'obsVersion': '30.0.0'};
          }),
        ),
      );

    expect(await registry.checkHealth('obs'), isTrue);
    expect(requests, ['GetVersion']);
  });

  test('reports OBS health transport failures', () async {
    final registry = DartPluginRegistry()
      ..register(
        createObsPlugin(
          CallbackObsTransport((request, data) async {
            throw StateError('OBS is offline');
          }),
        ),
      );

    expect(() => registry.checkHealth('obs'), throwsA(isA<StateError>()));
  });

  test('validates and persists OBS connection settings', () async {
    final directory = await Directory.systemTemp.createTemp('showrunner-obs-');
    addTearDown(() => directory.delete(recursive: true));
    final dataService = ShowRunnerDataService(directory);

    final invalid = validateProviderSettings('obs', {
      'host': '',
      'port': 70000,
    });
    expect(invalid.isValid, isFalse);

    final settings = {'host': 'obs.local', 'port': 4456, 'password': 'updated'};
    expect(validateProviderSettings('obs', settings).isValid, isTrue);
    await dataService.savePluginSettings('obs', settings);

    expect(await dataService.loadPluginSettings('obs'), {
      'host': 'obs.local',
      'port': 4456,
      'password': 'updated',
    });
  });

  test(
    'routes transform actions with the OBS WebSocket payload shape',
    () async {
      Map<String, dynamic>? requestData;
      final registry = DartPluginRegistry()
        ..register(
          createObsPlugin(
            CallbackObsTransport((request, data) async {
              requestData = data;
              return {};
            }),
          ),
        );

      await registry.invokeAction('obs', 'transform', {
        'scene': 'Main',
        'source': 7,
        'transform': {
          'position': {'x': 100},
          'scale': {'x': 2, 'y': 2},
        },
      });

      expect(requestData?['sceneName'], 'Main');
      expect(requestData?['sceneItemId'], 7);
      expect(requestData?['sceneItemTransform'], {
        'positionX': 100,
        'scaleX': 2,
        'scaleY': 2,
      });
    },
  );

  test('reads and writes OBS input settings through actions', () async {
    final requests = <(String, Map<String, dynamic>)>[];
    final registry = DartPluginRegistry()
      ..register(
        createObsPlugin(
          CallbackObsTransport((request, data) async {
            requests.add((request, data));
            if (request == 'GetInputSettings') {
              return {
                'inputName': 'Camera',
                'inputSettings': {'device_id': 'camera-1'},
              };
            }
            return {};
          }),
        ),
      );

    final current = await registry.invokeAction('obs', 'getInputSettings', {
      'sourceName': 'Camera',
    });
    await registry.invokeAction('obs', 'setInputSettings', {
      'sourceName': 'Camera',
      'inputSettings': {'device_id': 'camera-2'},
    });

    expect((current as Map)['inputSettings'], {'device_id': 'camera-1'});
    expect(requests.map((entry) => entry.$1), [
      'GetInputSettings',
      'SetInputSettings',
    ]);
    expect(requests[0].$2['inputName'], 'Camera');
    expect(requests[1].$2, {
      'inputName': 'Camera',
      'inputSettings': {'device_id': 'camera-2'},
    });
  });
}
