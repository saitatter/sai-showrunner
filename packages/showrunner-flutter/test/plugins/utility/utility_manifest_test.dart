import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/http/manifest.dart';
import 'package:showrunner_flutter/plugins/overlays/manifest.dart';
import 'package:showrunner_flutter/plugins/random/manifest.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/plugins/time/manifest.dart';
import 'package:showrunner_flutter/plugins/variables/manifest.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';

void main() {
  test('utility actions expose structured configuration schemas', () {
    final plugins = [
      createHttpPlugin(),
      createOverlaysPlugin(),
      createRandomPlugin(),
      createTimePlugin(),
      createVariablesPlugin(),
    ];

    for (final plugin in plugins) {
      for (final action in plugin.actions) {
        expect(
          action.configSchema,
          isNotNull,
          reason: '${plugin.id}:${action.actionId}',
        );
      }
    }
    expect(
      createHttpPlugin().actions.single.configSchema!.fields.map(
        (field) => field.key,
      ),
      ['url', 'method', 'query', 'contentType', 'headers', 'body'],
    );
    expect(
      createRandomPlugin().actions.first.configSchema!.fields.map(
        (field) => field.key,
      ),
      ['min', 'max'],
    );
    expect(
      createVariablesPlugin().actions
          .firstWhere((action) => action.actionId == 'offsetViewerVar')
          .configSchema!
          .fields
          .map((field) => field.key),
      ['viewer', 'variable', 'offset'],
    );
  });

  test('overlay action emits its configured widget event', () async {
    final eventHub = DartPluginEventHub();
    final event = eventHub.stream('overlayWidget').first;
    final registry = DartPluginRegistry()
      ..register(createOverlaysPlugin(eventHub: eventHub));

    expect(
      await registry.invokeAction('overlays', 'triggerWidget', {
        'widgetId': 'alert',
        'overlayId': 'main',
        'payload': {'message': 'Hello'},
      }),
      {'triggered': true, 'widgetId': 'alert'},
    );
    expect(await event, {
      'widgetId': 'alert',
      'overlayId': 'main',
      'payload': {'message': 'Hello'},
    });
    await eventHub.dispose();
  });

  test(
    'random wheel actions and triggers preserve overlay RPC routing',
    () async {
      final eventHub = DartPluginEventHub();
      final registry = DartPluginRegistry()
        ..register(createRandomPlugin(eventHub: eventHub));
      final outgoing = eventHub.stream(OverlayEventIds.widgetRpc).first;
      await registry.invokeAction('random', 'spinWheel', {
        'wheel': {'overlayId': 'main', 'widgetId': 'wheel'},
        'strength': 2,
      });
      expect(await outgoing, {
        'overlayId': 'main',
        'widgetId': 'wheel',
        'rpcId': 'spinWheel',
        'args': [2.0],
      });

      final trigger = registry.findTrigger('random', 'wheelLanded')!;
      final incoming = trigger.listen().first;
      eventHub.emit(OverlayEventIds.widgetRpc, {
        'overlayId': 'main',
        'widgetId': 'wheel',
        'rpcId': 'wheelLanded',
        'args': ['Prize'],
      });
      expect(await incoming, {
        'wheel': {'overlayId': 'main', 'widgetId': 'wheel'},
        'item': 'Prize',
      });
      await registry.close();
      await eventHub.dispose();
    },
  );

  test(
    'overlay actions preserve the broadcast and widget RPC payloads',
    () async {
      final eventHub = DartPluginEventHub();
      final registry = DartPluginRegistry()
        ..register(createOverlaysPlugin(eventHub: eventHub));

      final alertEvent = eventHub.stream(OverlayEventIds.widgetRpc).first;
      await registry.invokeAction('overlays', 'alert', {
        'alert': {'overlayId': 'main', 'widgetId': 'alert'},
        'title': 'Hello',
        'subtitle': 'World',
      });
      expect(await alertEvent, {
        'overlayId': 'main',
        'widgetId': 'alert',
        'rpcId': 'showAlert',
        'args': ['Hello', 'World', 0],
      });

      final chatEvent = eventHub.stream(OverlayEventIds.broadcast).first;
      await registry.invokeAction('overlays', 'pushChatMessage', {
        'targetWidget': {'overlayId': 'main', 'widgetId': 'chat'},
        'messageId': 'message-1',
        'viewerName': 'viewer',
        'message': 'Hi',
        'platform': 'twitch',
      });
      expect(await chatEvent, {
        'broadcastId': 'showrunner_chat_message',
        'payload': {
          'targetOverlayId': 'main',
          'targetWidgetId': 'chat',
          'id': 'message-1',
          'platform': 'twitch',
          'displayName': 'viewer',
          'username': 'viewer',
          'message': 'Hi',
          'badges': '',
        },
      });

      final sceneEvent = eventHub.stream(OverlayEventIds.broadcast).first;
      await registry.invokeAction('overlays', 'beginSceneOverlay', {
        'sceneKey': 'starting',
        'title': 'Starting soon',
      });
      expect(await sceneEvent, {
        'broadcastId': 'showrunner_scene_event',
        'payload': {
          'type': 'scene.begin',
          'targetOverlayId': '',
          'targetWidgetId': '',
          'sceneKey': 'starting',
          'title': 'Starting soon',
          'subtitle': '',
          'accentColor': '#9146ff',
        },
      });
      await eventHub.dispose();
    },
  );

  test('widget visibility updates and persists the overlay resource', () async {
    final eventHub = DartPluginEventHub();
    ResourceData? saved;
    final store = OverlayResourceStore(
      load: (id) async => id == 'main'
          ? ResourceData(
              id: id,
              config: {
                'name': 'Main',
                'widgets': [
                  {'id': 'chat', 'visible': true},
                ],
              },
            )
          : null,
      save: (resource) async => saved = resource,
    );
    final registry = DartPluginRegistry()
      ..register(createOverlaysPlugin(eventHub: eventHub, overlayStore: store));
    final configChanged = eventHub.stream(OverlayEventIds.configChanged).first;

    expect(
      await registry.invokeAction('overlays', 'widgetVisibility', {
        'widget': {'overlayId': 'main', 'widgetId': 'chat'},
        'enabled': 'toggle',
      }),
      {'widgetVisible': false},
    );
    expect(saved?.config['widgets'], [
      {'id': 'chat', 'visible': false},
    ]);
    expect(await configChanged, {
      'overlayId': 'main',
      'widgetId': 'chat',
      'visible': false,
    });
    await registry.close();
    await eventHub.dispose();
  });

  test('alert action selects an available weighted media entry', () async {
    final eventHub = DartPluginEventHub();
    final store = OverlayResourceStore(
      load: (id) async => ResourceData(
        id: id,
        config: {
          'widgets': [
            {
              'id': 'alert',
              'config': {
                'media': [
                  {'weight': 0, 'duration': 1},
                  {'weight': 1, 'duration': 1},
                ],
              },
            },
          ],
        },
      ),
      save: (_) async {},
    );
    final registry = DartPluginRegistry()
      ..register(createOverlaysPlugin(eventHub: eventHub, overlayStore: store));
    final rpcEvent = eventHub.stream(OverlayEventIds.widgetRpc).first;

    await registry.invokeAction('overlays', 'alert', {
      'alert': {'overlayId': 'main', 'widgetId': 'alert'},
      'title': 'Alert',
      'subtitle': '',
    });

    expect(await rpcEvent, {
      'overlayId': 'main',
      'widgetId': 'alert',
      'rpcId': 'showAlert',
      'args': ['Alert', '', 1],
    });
    await registry.close();
    await eventHub.dispose();
  });

  test('time action accepts dropdown toggle values', () async {
    final registry = DartPluginRegistry()..register(createTimePlugin());
    await registry.invokeAction('time', 'setTimer', {
      'timer': 'utility-test',
      'duration': 5,
    });

    expect(
      await registry.invokeAction('time', 'toggleTimer', {
        'timer': 'utility-test',
        'on': 'false',
      }),
      {'timerRunning': false},
    );
    expect(
      await registry.invokeAction('time', 'toggleTimer', {
        'timer': 'utility-test',
        'on': 'true',
      }),
      {'timerRunning': true},
    );
  });

  test(
    'time triggers preserve repeat and timer scheduling semantics',
    () async {
      final plugin = createTimePlugin();
      final repeat = plugin.triggers.firstWhere(
        (trigger) => trigger.triggerId == 'repeat',
      );
      final repeatEvent = await repeat.listenForConfig!
          .call({'delay': 0.01, 'interval': 0.1})
          .first
          .timeout(const Duration(seconds: 1));
      expect(repeatEvent['timestamp'], isNotNull);

      final timer = plugin.triggers.firstWhere(
        (trigger) => trigger.triggerId == 'timer',
      );
      final registry = DartPluginRegistry()..register(plugin);
      await registry.invokeAction('time', 'setTimer', {
        'timer': 'utility-trigger',
        'duration': 0.2,
      });
      await registry.invokeAction('time', 'toggleTimer', {
        'timer': 'utility-trigger',
        'on': true,
      });
      final timerEvent = await timer.listenForConfig!
          .call({'timer': 'utility-trigger', 'offset': 0})
          .first
          .timeout(const Duration(seconds: 1));
      expect(timerEvent['timer'], 'utility-trigger');
      await registry.close();
    },
  );
}
