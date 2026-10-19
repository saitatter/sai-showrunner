import '../../plugins/registry/plugin_registry.dart';

bool pluginMatchesSearch(DartPluginManifest plugin, String query) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) return true;
  final searchable = <String>[
    plugin.id.value,
    plugin.name,
    for (final action in plugin.actions) ...[
      action.actionId.value,
      action.displayName ?? '',
    ],
    for (final trigger in plugin.triggers) ...[
      trigger.triggerId.value,
      trigger.displayName,
    ],
    for (final setting in plugin.settings) ...[
      setting.id.value,
      setting.displayName,
    ],
    for (final state in plugin.states) ...[state.id.value, state.displayName],
  ];
  return searchable.any(
    (value) => value.toLowerCase().contains(normalizedQuery),
  );
}

List<DartPluginManifest> filterPlugins(
  Iterable<DartPluginManifest> plugins,
  String query,
) => [
  for (final plugin in plugins)
    if (pluginMatchesSearch(plugin, query)) plugin,
];
