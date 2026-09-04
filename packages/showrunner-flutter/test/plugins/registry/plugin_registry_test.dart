import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/obs/obs.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_bootstrap.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';

void main() {
  test('bootstraps migrated provider manifests into the Dart registry', () {
    final registry = createDefaultPluginRegistry();

    expect(
      registry.plugins.map((plugin) => plugin.id),
      containsAll(<String>[
        'obs',
        'youtube',
        'twitch',
        'discord',
        'bluesky',
        'donordrive',
        'aitum',
        'advss',
        'remote',
        'voicemod',
        'sound',
        'minecraft',
        'http',
        'time',
        'os',
        'random',
        'variables',
        'overlays',
        'spellcast',
        'iot',
        'govee',
        'philips-hue',
        'twinkly',
        'elgato',
        'tplink-kasa',
      ]),
    );
    expect(registry.findAction('obs', 'scene'), isNotNull);
    expect(registry.findAction('youtube', 'sendChatMessage'), isNotNull);
    expect(registry.findAction('twitch', 'chat'), isNotNull);
    expect(registry.findAction('discord', 'discordMessage'), isNotNull);
    expect(registry.findAction('bluesky', 'post'), isNotNull);
    expect(registry.findTrigger('donordrive', 'donation'), isNull);
    expect(registry.findAction('aitum', 'verticalScene'), isNotNull);
    expect(registry.findAction('advss', 'AdvSSMessage'), isNotNull);
    expect(registry.findAction('sound', 'speakTTS'), isNotNull);
    expect(registry.findAction('variables', 'setViewerVar'), isNotNull);
    expect(registry.findAction('variables', 'offsetViewerVar'), isNotNull);
    expect(registry.findAction('minecraft', 'mineCmd'), isNotNull);
    expect(registry.findAction('http', 'request'), isNotNull);
    expect(registry.findAction('govee', 'setColor'), isNotNull);
    expect(registry.findAction('elgato', 'setLightState'), isNotNull);
    expect(registry.findAction('tplink-kasa', 'setLightState'), isNotNull);
  });

  test('bootstraps and executes the built-in conversion actions', () async {
    final registry = createDefaultPluginRegistry();

    expect(registry.findPlugin('ShowRunner'), isNotNull);
    expect(
      registry
          .findPlugin('ShowRunner')!
          .actions
          .map((action) => action.actionId),
      containsAll(<String>[
        'convertNumberToString',
        'convertBooleanToString',
        'convertStringToNumber',
        'convertBooleanToNumber',
        'convertNumberToBoolean',
        'convertStringToBoolean',
        'convertObjectToJsonString',
        'convertArrayToJsonString',
        'convertJsonStringToObject',
        'convertJsonStringToArray',
      ]),
    );
    expect(
      await registry.invokeAction('ShowRunner', 'convertNumberToString', {
        'value': 12.5,
      }),
      {'value': '12.5'},
    );
    expect(
      await registry.invokeAction('ShowRunner', 'convertBooleanToString', {
        'value': false,
      }),
      {'value': 'false'},
    );
    expect(
      await registry.invokeAction('ShowRunner', 'convertStringToNumber', {
        'value': 'nope',
        'fallback': 7,
      }),
      {'value': 7, 'converted': false},
    );
    expect(
      await registry.invokeAction('ShowRunner', 'convertBooleanToNumber', {
        'value': true,
      }),
      {'value': 1},
    );
    expect(
      await registry.invokeAction('ShowRunner', 'convertNumberToBoolean', {
        'value': 0,
      }),
      {'value': false},
    );
    expect(
      await registry.invokeAction('ShowRunner', 'convertStringToBoolean', {
        'value': 'yes',
        'fallback': false,
      }),
      {'value': true, 'converted': true},
    );
    expect(
      await registry.invokeAction('ShowRunner', 'convertObjectToJsonString', {
        'value': {'answer': 42},
      }),
      {'value': '{"answer":42}'},
    );
    expect(
      await registry.invokeAction('ShowRunner', 'convertArrayToJsonString', {
        'value': [1, 2],
      }),
      {'value': '[1,2]'},
    );
    expect(
      await registry.invokeAction('ShowRunner', 'convertJsonStringToObject', {
        'value': '[1,2]',
      }),
      {'value': <String, dynamic>{}, 'converted': false},
    );
    expect(
      await registry.invokeAction('ShowRunner', 'convertJsonStringToArray', {
        'value': '[1,2]',
      }),
      {
        'value': [1, 2],
        'converted': true,
      },
    );
  });

  test('tracks plugin runtime state and prevents disabled plugin actions', () {
    final registry = createDefaultPluginRegistry();
    expect(registry.stateValues('obs')['connection'], 'unconfigured');
    registry.updateState('obs', 'connection', 'connected');
    expect(registry.stateValues('obs')['connection'], 'connected');
    registry.setPluginEnabled('obs', false);
    expect(registry.isPluginEnabled('obs'), isFalse);
  });

  test('invokes registered plugin actions directly for UI controls', () async {
    final requests = <String>[];
    final registry = DartPluginRegistry();
    registry.register(
      createObsPlugin(
        CallbackObsTransport((request, data) async {
          requests.add(request);
          return const <String, dynamic>{};
        }),
      ),
    );

    await registry.invokeAction('obs', 'streamStartStop', {
      'streaming': 'toggle',
    });

    expect(requests, ['ToggleStream']);
  });

  test('discovers Dart plugin settings, triggers, and health', () async {
    final registry = DartPluginRegistry();
    registry.register(
      DartPluginManifest(
        id: 'sample',
        name: 'Sample',
        settings: const [
          DartSettingDefinition(
            id: 'token',
            displayName: 'Token',
            secret: true,
          ),
        ],
        triggers: [
          DartTriggerDefinition(
            pluginId: 'sample',
            triggerId: 'event',
            displayName: 'Event',
            listen: () async* {
              yield {'value': 1};
            },
          ),
        ],
        healthCheck: () async => true,
      ),
    );

    final trigger = registry.findTrigger('sample', 'event');
    expect(registry.findPlugin('sample')?.settings.single.secret, isTrue);
    expect(await registry.checkHealth('sample'), isTrue);
    expect(await trigger!.listen().first, {'value': 1});
  });

  test('closes registered plugin runtimes', () async {
    var closed = false;
    final registry = DartPluginRegistry()
      ..register(
        DartPluginManifest(
          id: 'lifecycle',
          name: 'Lifecycle',
          dispose: () async => closed = true,
        ),
      );

    await registry.close();

    expect(closed, isTrue);
  });
}
