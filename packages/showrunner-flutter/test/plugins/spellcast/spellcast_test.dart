import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/components/data_inputs/data_input.dart';
import 'package:showrunner_flutter/plugins/spellcast/manifest.dart';
import 'package:showrunner_flutter/plugins/overlays/manifest.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';

void main() {
  test('registers the Spellcast trigger with resource-aware matching', () {
    final hub = DartPluginEventHub();
    final plugin = createSpellcastPlugin(eventHub: hub);
    final trigger = plugin.triggers.single;

    expect(trigger.triggerId, 'spellHook');
    expect(trigger.configSchema?.key, 'spell');
    expect(trigger.configSchema?.kind, DartDataInputKind.resource);
    expect(trigger.configSchema?.resourceType, 'SpellHook');
    expect(
      trigger.matches?.call(
        {'spell': 'local-spell'},
        {'spellId': 'local-spell', 'viewer': 'viewer-1', 'bits': 100},
      ),
      isTrue,
    );
    expect(
      trigger.matches?.call(
        {
          'spell': {'id': 'local-spell'},
        },
        {
          'spell': {'resourceId': 'other-spell'},
        },
      ),
      isFalse,
    );
  });

  test('Spellcast events can drive a profile trigger stream', () async {
    final hub = DartPluginEventHub();
    final plugin = createSpellcastPlugin(eventHub: hub);
    final trigger = plugin.triggers.single;
    final events = <RuntimeMap>[];
    final subscription = trigger.listen().listen(events.add);

    hub.emit('spellcast', {
      'spellId': 'spell-1',
      'viewer': 'viewer-1',
      'bits': 50,
    });
    await Future<void>.delayed(Duration.zero);

    expect(events, [
      {'spellId': 'spell-1', 'viewer': 'viewer-1', 'bits': 50},
    ]);
    await subscription.cancel();
    await hub.dispose();
  });

  test(
    'castSpell emits a command event for local automation consumers',
    () async {
      final hub = DartPluginEventHub();
      final plugin = createSpellcastPlugin(eventHub: hub);
      final events = <RuntimeMap>[];
      final subscription = hub.stream('spellcastCommand').listen(events.add);

      expect(
        await plugin.actions.single.invoke({
          'spellId': 'spell-1',
        }, EvaluationContext()),
        {'cast': true, 'spellId': 'spell-1'},
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, [
        {'spellId': 'spell-1'},
      ]);

      await subscription.cancel();
      await hub.dispose();
    },
  );

  test(
    'triggerWidget emits an overlay event for local automation consumers',
    () async {
      final hub = DartPluginEventHub();
      final plugin = createOverlaysPlugin(eventHub: hub);
      final events = <RuntimeMap>[];
      final subscription = hub.stream('overlayWidget').listen(events.add);

      expect(
        await plugin.actions.single.invoke({
          'widgetId': 'alert-1',
          'overlayId': 'overlay-1',
          'payload': {'message': 'Hello'},
        }, EvaluationContext()),
        {'triggered': true, 'widgetId': 'alert-1'},
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, [
        {
          'widgetId': 'alert-1',
          'overlayId': 'overlay-1',
          'payload': {'message': 'Hello'},
        },
      ]);

      await subscription.cancel();
      await hub.dispose();
    },
  );
}
