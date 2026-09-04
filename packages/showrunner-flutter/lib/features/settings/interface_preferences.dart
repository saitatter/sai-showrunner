import 'package:flutter/foundation.dart';

import '../../plugins/registry/plugin_registry.dart';
import '../../services/showrunner_data_service.dart';

final class FlutterInterfacePreferences extends ChangeNotifier {
  FlutterInterfacePreferences({required this.dataService});

  static const _defaults = <String, bool>{
    'compactProjectSidebar': false,
    'hideDisabledIntegrations': false,
    'hideNativeIntegrationShortcuts': true,
    'collapseIntegrationCategoriesByDefault': false,
    'showPluginSwitches': true,
  };

  final ShowRunnerDataService dataService;
  final Map<String, bool> _values = Map<String, bool>.from(_defaults);
  bool _loading = true;
  bool _saving = false;

  bool get isLoading => _loading;
  bool get isSaving => _saving;

  bool value(String key) => _values[key] ?? false;

  bool get compactProjectSidebar => value('compactProjectSidebar');
  bool get hideDisabledIntegrations => value('hideDisabledIntegrations');
  bool get hideNativeIntegrationShortcuts =>
      value('hideNativeIntegrationShortcuts');
  bool get collapseIntegrationCategoriesByDefault =>
      value('collapseIntegrationCategoriesByDefault');
  bool get showPluginSwitches => value('showPluginSwitches');

  Future<void> load() async {
    try {
      final settings = await dataService.loadPluginSettings(
        'showrunner-flutter',
      );
      for (final entry in _defaults.entries) {
        final value = settings[entry.key];
        if (value is bool) _values[entry.key] = value;
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> setValue(String key, bool value) async {
    if (!_defaults.containsKey(key)) {
      throw ArgumentError.value(key, 'key');
    }
    final previous = _values[key]!;
    _values[key] = value;
    notifyListeners();
    try {
      await _saveValues();
    } catch (_) {
      _values[key] = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> reset() async {
    final previous = Map<String, bool>.from(_values);
    _values
      ..clear()
      ..addAll(_defaults);
    notifyListeners();
    try {
      await _saveValues();
    } catch (_) {
      _values
        ..clear()
        ..addAll(previous);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> enableAllPlugins(DartPluginRegistry registry) async {
    final settings = await dataService.loadPluginSettings('showrunner-flutter');
    await dataService.savePluginSettings('showrunner-flutter', {
      ...settings,
      'disabledPlugins': <String>[],
    });
    for (final plugin in registry.plugins) {
      registry.setPluginEnabled(plugin.id, true);
    }
  }

  Future<void> _saveValues() async {
    _saving = true;
    notifyListeners();
    try {
      final settings = await dataService.loadPluginSettings(
        'showrunner-flutter',
      );
      await dataService.savePluginSettings('showrunner-flutter', {
        ...settings,
        ..._values,
      });
    } finally {
      _saving = false;
      notifyListeners();
    }
  }
}

final class InterfacePreferenceDefinition {
  const InterfacePreferenceDefinition({
    required this.key,
    required this.title,
    required this.description,
  });

  final String key;
  final String title;
  final String description;
}

const interfacePreferenceDefinitions = <InterfacePreferenceDefinition>[
  InterfacePreferenceDefinition(
    key: 'compactProjectSidebar',
    title: 'Compact integration sidebar',
    description: 'Use denser rows and a narrower integrations column.',
  ),
  InterfacePreferenceDefinition(
    key: 'hideDisabledIntegrations',
    title: 'Hide disabled integrations',
    description: 'Remove disabled plugins from the left integrations catalog.',
  ),
  InterfacePreferenceDefinition(
    key: 'hideNativeIntegrationShortcuts',
    title: 'Hide duplicate native shortcuts',
    description: 'Keep core providers in the integrations catalog only.',
  ),
  InterfacePreferenceDefinition(
    key: 'collapseIntegrationCategoriesByDefault',
    title: 'Collapse integration categories by default',
    description: 'Start grouped integration sections collapsed.',
  ),
  InterfacePreferenceDefinition(
    key: 'showPluginSwitches',
    title: 'Show plugin switches in sidebar',
    description: 'Display enable and disable controls beside each plugin.',
  ),
];
