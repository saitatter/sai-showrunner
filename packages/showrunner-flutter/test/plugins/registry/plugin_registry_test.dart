import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/obs/obs.dart';
import 'package:showrunner_flutter/plugins/contracts/identifiers.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_bootstrap.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/domain/errors/showrunner_error.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_health.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_host_context.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_module.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_ui.dart';

void main() {
  test('keeps Flutter UI contributions outside the plugin manifest', () {
    final registry = DartPluginRegistry()
      ..register(const DartPluginManifest(id: 'sample', name: 'Sample'));
    final contribution = DartFlutterPluginUiContribution(
      builder: (context, dataService, providerEvents, registryFuture) =>
          const SizedBox.shrink(),
    );

    registry.registerUi('sample', contribution);

    expect(registry.uiFor('sample'), same(contribution));
    expect(
      () => registry.registerUi('unknown', contribution),
      throwsArgumentError,
    );
    expect(
      () => registry.registerUi('sample', contribution),
      throwsArgumentError,
    );
  });

  test('keeps plugin contract keys typed and collision-safe', () {
    const obs = PluginId('obs');
    const action = ActionId('scene');
    expect(
      const ActionKey(plugin: PluginId('obs'), action: ActionId('scene')),
      const ActionKey(plugin: obs, action: action),
    );
    expect(
      const TriggerKey(plugin: PluginId('obs'), trigger: TriggerId('scene')),
      isNot(
        const TriggerKey(
          plugin: PluginId('twitch'),
          trigger: TriggerId('scene'),
        ),
      ),
    );

    final registry = DartPluginRegistry();
    registry.register(const DartPluginManifest(id: 'sample', name: 'Sample'));
    expect(
      () => registry.register(
        const DartPluginManifest(id: 'sample', name: 'Duplicate'),
      ),
      throwsArgumentError,
    );
  });

  test('bootstraps provider manifests into the Dart registry', () {
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
        'lifx',
        'wyze',
        'dashboards',
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
    expect(registry.findAction('moderation', 'moderateChatMessage'), isNotNull);
    expect(registry.findAction('minecraft', 'mineCmd'), isNotNull);
    expect(registry.findAction('http', 'request'), isNotNull);
    expect(registry.findAction('govee', 'setColor'), isNotNull);
    expect(registry.findAction('elgato', 'setLightState'), isNotNull);
    expect(registry.findAction('tplink-kasa', 'setLightState'), isNotNull);
    expect(registry.findAction('lifx', 'setLightState'), isNotNull);
    expect(registry.findAction('wyze', 'setLightState'), isNotNull);
    expect(registry.findPlugin('dashboards'), isNotNull);
    expect(registry.uiFor('discord'), isNotNull);
    expect(registry.uiFor('minecraft'), isNotNull);
    expect(registry.uiFor('dashboards'), isNotNull);
    expect(registry.uiFor('overlays'), isNotNull);
    expect(registry.uiFor('remote'), isNotNull);
    expect(registry.uiFor('stream-plans'), isNotNull);
    expect(registry.uiFor('sound'), isNotNull);
    expect(registry.uiFor('variables'), isNotNull);
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

  test('tracks plugin runtime state and notifies listeners', () {
    final registry = createDefaultPluginRegistry();
    var notifications = 0;
    registry.addListener(() => notifications++);
    expect(registry.stateValues('obs')['connection'], 'unconfigured');
    registry.updateState('obs', 'connection', 'connected');
    expect(registry.stateValues('obs')['connection'], 'connected');
    expect(
      registry.stateContext()['obs'],
      containsPair('connection', 'connected'),
    );
    expect(notifications, 1);
    registry.updateState('obs', 'connection', 'connected');
    expect(notifications, 1);
    registry.setPluginEnabled('obs', false);
    expect(registry.isPluginEnabled('obs'), isFalse);
    expect(notifications, 2);
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

  test('reports disabled and missing actions with typed errors', () {
    final registry = DartPluginRegistry()
      ..register(const DartPluginManifest(id: 'sample', name: 'Sample'));
    registry.setPluginEnabled('sample', false);

    expect(
      () => registry.invokeAction('sample', 'run', const {}),
      throwsA(isA<PluginConfigurationError>()),
    );
    registry.setPluginEnabled('sample', true);
    expect(
      () => registry.invokeAction('sample', 'run', const {}),
      throwsA(isA<ActionExecutionError>()),
    );
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
    var closeCount = 0;
    final registry = DartPluginRegistry()
      ..register(
        DartPluginManifest(
          id: 'lifecycle',
          name: 'Lifecycle',
          dispose: () async => closeCount++,
        ),
      );

    await Future.wait([registry.close(), registry.close()]);

    expect(closeCount, 1);
    expect(
      () =>
          registry.register(const DartPluginManifest(id: 'late', name: 'Late')),
      throwsStateError,
    );
  });

  test(
    'starts plugin runtimes in registration order and stops them once',
    () async {
      final events = <String>[];
      final registry = DartPluginRegistry()
        ..register(
          DartPluginManifest(
            id: 'first',
            name: 'First',
            start: () async => events.add('start:first'),
            stop: () async => events.add('stop:first'),
          ),
        )
        ..register(
          DartPluginManifest(
            id: 'second',
            name: 'Second',
            start: () async => events.add('start:second'),
            stop: () async => events.add('stop:second'),
          ),
        );

      await Future.wait([registry.start(), registry.start()]);
      await registry.close();

      expect(events, [
        'start:first',
        'start:second',
        'stop:second',
        'stop:first',
      ]);
    },
  );

  test('registers module lifecycle independently from its manifest', () async {
    final events = <String>[];
    final module = _TestPluginModule(events);
    final registry = DartPluginRegistry()..registerModule(module);

    await registry.initialize(
      const DartPluginHostContext(services: {'source': 'test'}),
    );
    await registry.start();
    expect(await module.checkHealth(), const DartPluginHealth.ready());
    expect(await registry.checkHealth('module'), isTrue);
    await registry.close();

    expect(events, ['initialize:test', 'start', 'stop']);
  });

  test('continues shutdown when a module stop hook fails', () async {
    final events = <String>[];
    final registry = DartPluginRegistry()
      ..registerModule(_StopFailureModule(events, 'first', fails: true))
      ..registerModule(_StopFailureModule(events, 'second'));

    await expectLater(registry.close, throwsA(isA<StateError>()));
    expect(events, ['stop:second', 'stop:first']);
  });
}

final class _TestPluginModule implements DartPluginModule {
  _TestPluginModule(this.events);

  final List<String> events;

  @override
  final manifest = const DartPluginManifest(id: 'module', name: 'Module');

  @override
  Future<void> initialize(DartPluginHostContext host) async {
    events.add('initialize:${host.service<String>('source')}');
  }

  @override
  Future<void> start() async => events.add('start');

  @override
  Future<void> stop() async => events.add('stop');

  @override
  Future<DartPluginHealth> checkHealth() async =>
      const DartPluginHealth.ready();
}

final class _StopFailureModule implements DartPluginModule {
  _StopFailureModule(this.events, this.id, {this.fails = false});

  final List<String> events;
  final String id;
  final bool fails;

  @override
  DartPluginManifest get manifest => DartPluginManifest(id: id, name: id);

  @override
  Future<void> initialize(DartPluginHostContext host) async {}

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {
    events.add('stop:$id');
    if (fails) throw StateError('stop failed: $id');
  }

  @override
  Future<DartPluginHealth> checkHealth() async =>
      const DartPluginHealth.ready();
}
