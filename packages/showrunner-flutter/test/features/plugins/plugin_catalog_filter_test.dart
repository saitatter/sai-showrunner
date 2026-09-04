import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/plugins/plugin_catalog_filter.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/runtime/expression.dart';

void main() {
  const plugin = DartPluginManifest(
    id: 'obs',
    name: 'OBS Studio',
    actions: [
      DartActionDefinition(
        pluginId: 'obs',
        actionId: 'browserRefresh',
        displayName: 'Refresh browser source',
        invoke: _noopAction,
      ),
    ],
    triggers: [
      DartTriggerDefinition(
        pluginId: 'obs',
        triggerId: 'sceneChanged',
        displayName: 'Scene changed',
        listen: _noopTrigger,
      ),
    ],
    settings: [DartSettingDefinition(id: 'host', displayName: 'OBS host')],
  );

  test('matches plugin metadata and registered capabilities', () {
    expect(pluginMatchesSearch(plugin, 'studio'), isTrue);
    expect(pluginMatchesSearch(plugin, 'refresh browser'), isTrue);
    expect(pluginMatchesSearch(plugin, 'sceneChanged'), isTrue);
    expect(pluginMatchesSearch(plugin, 'OBS host'), isTrue);
    expect(pluginMatchesSearch(plugin, 'missing'), isFalse);
  });

  test('filters grouped catalog entries without changing their order', () {
    const twitch = DartPluginManifest(id: 'twitch', name: 'Twitch');
    expect(filterPlugins([plugin, twitch], 'twitch'), [twitch]);
    expect(filterPlugins([plugin, twitch], ''), [plugin, twitch]);
  });
}

Future<Object?> _noopAction(
  RuntimeMap config,
  EvaluationContext context,
) async => null;

Stream<RuntimeMap> _noopTrigger() => const Stream.empty();
