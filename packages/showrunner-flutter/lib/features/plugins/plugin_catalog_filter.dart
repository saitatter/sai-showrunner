import '../../plugins/registry/plugin_registry.dart';

bool pluginMatchesSearch(DartPluginManifest plugin, String query) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) return true;
  final searchable = <String>[
    plugin.id,
    plugin.name,
    for (final action in plugin.actions) ...[
      action.actionId,
      action.displayName ?? '',
    ],
    for (final trigger in plugin.triggers) ...[
      trigger.triggerId,
      trigger.displayName,
    ],
    for (final setting in plugin.settings) ...[setting.id, setting.displayName],
    for (final state in plugin.states) ...[state.id, state.displayName],
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
