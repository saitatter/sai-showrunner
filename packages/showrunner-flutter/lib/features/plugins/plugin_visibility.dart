import '../../plugins/registry/plugin_registry.dart';
import '../../services/showrunner_data_service.dart';

Future<void> persistPluginEnabled({
  required ShowRunnerDataService dataService,
  required DartPluginRegistry registry,
  required String pluginId,
  required bool enabled,
}) {
  final typedPluginId = PluginId(pluginId);
  return registry.setEnabled(
    typedPluginId,
    enabled,
    persist: (nextEnabled) =>
        dataService.transformPluginSettings('showrunner-flutter', (settings) {
          final disabled = <String>{
            if (settings['disabledPlugins'] is List)
              ...((settings['disabledPlugins'] as List).whereType<String>()),
          };
          if (nextEnabled) {
            disabled.remove(pluginId);
          } else {
            disabled.add(pluginId);
          }
          return {...settings, 'disabledPlugins': disabled.toList()..sort()};
        }),
  );
}
