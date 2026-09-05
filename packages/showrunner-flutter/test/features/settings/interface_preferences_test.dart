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
        'projectSidebarWidth': 360,
      });

      final preferences = FlutterInterfacePreferences(dataService: dataService);
      await preferences.load();
      expect(preferences.hideDisabledIntegrations, isTrue);
      expect(preferences.projectSidebarWidth, 360);

      await preferences.setValue('showPluginSwitches', false);
      await preferences.setProjectSidebarWidth(500);
      final saved = await dataService.loadPluginSettings('showrunner-flutter');
      expect(saved['hideDisabledIntegrations'], isTrue);
      expect(saved['showPluginSwitches'], isFalse);
      expect(saved['disabledPlugins'], ['obs']);
      expect(saved['projectSidebarWidth'], 420);
      await preferences.setProjectSidebarWidth(100);
      expect(preferences.projectSidebarWidth, 208);
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
      await preferences.setProjectSidebarWidth(360);
      await preferences.reset();

      expect(preferences.compactProjectSidebar, isFalse);
      expect(preferences.hideNativeIntegrationShortcuts, isTrue);
      expect(
        preferences.projectSidebarWidth,
        FlutterInterfacePreferences.defaultProjectSidebarWidth,
      );
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
