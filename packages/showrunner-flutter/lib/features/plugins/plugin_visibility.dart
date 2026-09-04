import '../../plugins/registry/plugin_registry.dart';
import '../../services/showrunner_data_service.dart';

Future<void> persistPluginEnabled({
  required ShowRunnerDataService dataService,
  required DartPluginRegistry registry,
  required String pluginId,
  required bool enabled,
}) async {
  final previous = registry.isPluginEnabled(pluginId);
  registry.setPluginEnabled(pluginId, enabled);
  try {
    final settings = await dataService.loadPluginSettings('showrunner-flutter');
    final disabled = <String>{
      if (settings['disabledPlugins'] is List)
        ...((settings['disabledPlugins'] as List).whereType<String>()),
    };
    if (enabled) {
      disabled.remove(pluginId);
    } else {
      disabled.add(pluginId);
    }
    await dataService.savePluginSettings('showrunner-flutter', {
      ...settings,
      'disabledPlugins': disabled.toList()..sort(),
    });
  } catch (_) {
    registry.setPluginEnabled(pluginId, previous);
    rethrow;
  }
}
