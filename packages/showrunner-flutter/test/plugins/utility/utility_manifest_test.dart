import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/http/manifest.dart';
import 'package:showrunner_flutter/plugins/overlays/manifest.dart';
import 'package:showrunner_flutter/plugins/random/manifest.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
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
      ['url', 'method', 'contentType', 'headers', 'body'],
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
      {'timer': 'utility-test', 'running': false},
    );
    expect(
      await registry.invokeAction('time', 'toggleTimer', {
        'timer': 'utility-test',
        'on': 'true',
      }),
      {'timer': 'utility-test', 'running': true},
    );
  });
}
