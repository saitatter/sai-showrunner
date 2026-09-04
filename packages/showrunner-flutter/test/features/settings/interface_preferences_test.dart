import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/settings/interface_preferences.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  test(
    'loads and persists interface preferences without losing plugin state',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'showrunner-interface-preferences-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final dataService = ShowRunnerDataService(directory);
      await dataService.savePluginSettings('showrunner-flutter', {
        'disabledPlugins': ['obs'],
        'hideDisabledIntegrations': true,
      });

      final preferences = FlutterInterfacePreferences(dataService: dataService);
      await preferences.load();
      expect(preferences.hideDisabledIntegrations, isTrue);

      await preferences.setValue('showPluginSwitches', false);
      final saved = await dataService.loadPluginSettings('showrunner-flutter');
      expect(saved['hideDisabledIntegrations'], isTrue);
      expect(saved['showPluginSwitches'], isFalse);
      expect(saved['disabledPlugins'], ['obs']);
      preferences.dispose();
    },
  );

  test(
    'reset restores interface defaults and preserves disabled plugins',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'showrunner-interface-reset-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final dataService = ShowRunnerDataService(directory);
      await dataService.savePluginSettings('showrunner-flutter', {
        'disabledPlugins': ['twitch'],
        'compactProjectSidebar': true,
      });

      final preferences = FlutterInterfacePreferences(dataService: dataService);
      await preferences.load();
      await preferences.reset();

      expect(preferences.compactProjectSidebar, isFalse);
      expect(preferences.hideNativeIntegrationShortcuts, isTrue);
      expect(
        (await dataService.loadPluginSettings(
          'showrunner-flutter',
        ))['disabledPlugins'],
        ['twitch'],
      );
      preferences.dispose();
    },
  );

  test(
    'enables every registered plugin while preserving other settings',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'showrunner-enable-all-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final dataService = ShowRunnerDataService(directory);
      await dataService.savePluginSettings('showrunner-flutter', {
        'disabledPlugins': ['sample'],
        'showPluginSwitches': false,
      });
      final registry = DartPluginRegistry()
        ..register(const DartPluginManifest(id: 'sample', name: 'Sample'));
      registry.setPluginEnabled('sample', false);
      final preferences = FlutterInterfacePreferences(dataService: dataService);

      await preferences.enableAllPlugins(registry);

      expect(registry.isPluginEnabled('sample'), isTrue);
      final saved = await dataService.loadPluginSettings('showrunner-flutter');
      expect(saved['disabledPlugins'], isEmpty);
      expect(saved['showPluginSwitches'], isFalse);
      preferences.dispose();
    },
  );
}
