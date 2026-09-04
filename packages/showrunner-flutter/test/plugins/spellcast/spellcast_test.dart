import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/spellcast/manifest.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';

void main() {
  test('registers the Spellcast trigger with resource-aware matching', () {
    final hub = DartPluginEventHub();
    final plugin = createSpellcastPlugin(eventHub: hub);
    final trigger = plugin.triggers.single;

    expect(trigger.triggerId, 'spellHook');
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
}
