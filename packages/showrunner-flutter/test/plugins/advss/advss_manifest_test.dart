import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/advss/manifest.dart';
import 'package:showrunner_flutter/plugins/obs/actions.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';

void main() {
  test('sends Advanced Scene Switcher vendor messages through OBS', () async {
    dynamic payload;
    final registry = DartPluginRegistry()
      ..register(
        createAdvssPlugin(
          CallbackObsTransport((request, data) async {
            payload = data;
            return <String, dynamic>{'ok': true};
          }),
        ),
      );

    final result = await registry.invokeAction('advss', 'AdvSSMessage', {
      'message': 'scene-change',
    });

    expect(payload, {
      'vendorName': 'AdvancedSceneSwitcher',
      'requestType': 'AdvancedSceneSwitcherMessage',
      'requestData': {'message': 'scene-change'},
    });
    expect(result, {'ok': true});
  });

  test('matches configured Advanced Scene Switcher events', () async {
    final eventHub = DartPluginEventHub();
    final registry = DartPluginRegistry()
      ..register(
        createAdvssPlugin(
          CallbackObsTransport((request, data) async => {}),
          eventHub: eventHub,
        ),
      );
    final trigger = registry.findTrigger('advss', 'advssEvent')!;

    expect(
      trigger.matches!(
        {'message': 'hello'},
        {
          'vendorName': 'AdvancedSceneSwitcher',
          'eventType': 'AdvancedSceneSwitcherEvent',
          'message': 'hello',
        },
      ),
      isTrue,
    );
    expect(
      trigger.matches!(
        {'message': 'hello'},
        {
          'vendorName': 'other',
          'eventType': 'AdvancedSceneSwitcherEvent',
          'message': 'hello',
        },
      ),
      isFalse,
    );
    await eventHub.dispose();
  });
}
