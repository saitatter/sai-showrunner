import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/plugins/plugin_visibility.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  test(
    'concurrent collection edits preserve other plugins and settings owners',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'plugin-policy-race-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final data = ShowRunnerDataService(directory);
      final registries = List.generate(
        2,
        (index) => DartPluginRegistry()
          ..register(
            DartPluginManifest(
              id: PluginId('plugin-$index'),
              name: 'Plugin $index',
            ),
          ),
      );
      addTearDown(() async {
        for (final registry in registries) {
          await registry.close();
        }
      });
      await Future.wait([
        for (var index = 0; index < registries.length; index++)
          persistPluginEnabled(
            dataService: data,
            registry: registries[index],
            pluginId: 'plugin-$index',
            enabled: false,
          ),
        data.updatePluginSetting(
          'showrunner-flutter',
          'projectSidebarWidth',
          350,
        ),
      ]);
      final saved = await data.loadPluginSettings('showrunner-flutter');
      expect(saved['disabledPlugins'], ['plugin-0', 'plugin-1']);
      expect(saved['projectSidebarWidth'], 350);
    },
  );

  test('notifies listeners when plugin enabled state changes', () {
    final registry = DartPluginRegistry();
    registry.register(
      const DartPluginManifest(id: PluginId('sample'), name: 'Sample'),
    );
    var notifications = 0;
    registry.addListener(() => notifications++);

    registry.setPluginEnabled('sample', false);
    registry.setPluginEnabled('sample', false);
    registry.setPluginEnabled('sample', true);

    expect(notifications, 2);
    expect(registry.isPluginEnabled('sample'), isTrue);
  });

  test(
    'persists plugin visibility and rolls state through the registry',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'showrunner-plugin-visibility-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final dataService = ShowRunnerDataService(directory);
      final registry = DartPluginRegistry();
      registry.register(
        const DartPluginManifest(id: PluginId('sample'), name: 'Sample'),
      );

      await persistPluginEnabled(
        dataService: dataService,
        registry: registry,
        pluginId: 'sample',
        enabled: false,
      );

      expect(registry.isPluginEnabled('sample'), isFalse);
      expect(
        (await dataService.loadPluginSettings(
          'showrunner-flutter',
        ))['disabledPlugins'],
        ['sample'],
      );

      await persistPluginEnabled(
        dataService: dataService,
        registry: registry,
        pluginId: 'sample',
        enabled: true,
      );

      expect(registry.isPluginEnabled('sample'), isTrue);
      expect(
        (await dataService.loadPluginSettings(
          'showrunner-flutter',
        ))['disabledPlugins'],
        isEmpty,
      );
    },
  );
}
