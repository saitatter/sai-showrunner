import '../../plugins/registry/plugin_registry.dart';
import '../../persistence/document_revision.dart';
import '../../schema/json.dart';

/// Loaded settings/metadata are a form baseline, not a second persisted store.
class PluginSettingsSnapshot {
  PluginSettingsSnapshot._({
    required this.fields,
    required this.definitions,
    required this.values,
    required this.revisions,
  });
  final Map<String, List<String>> fields;
  final Map<String, DartSettingContract> definitions;
  final Map<String, JsonMap> values;
  final Map<String, DocumentRevision> revisions;
}

Future<PluginSettingsSnapshot> loadPluginSettingsSnapshot({
  required Future<DartPluginRegistry> registryFuture,
  required Future<JsonMap> Function(String pluginId) read,
}) async {
  final registry = await registryFuture;
  final fields = <String, List<String>>{},
      definitions = <String, DartSettingContract>{};
  final values = <String, JsonMap>{}, revisions = <String, DocumentRevision>{};
  for (final plugin in registry.plugins) {
    fields[plugin.id.value] = List.unmodifiable(
      plugin.settings.map((setting) => setting.id.value),
    );
    for (final setting in plugin.settings) {
      definitions['${plugin.id.value}:${setting.id.value}'] = setting;
    }
    if (plugin.settings.isEmpty) continue;
    final loaded = await read(plugin.id.value);
    values[plugin.id.value] = Map.unmodifiable(loaded);
    revisions[plugin.id.value] = DocumentRevision.of(loaded);
  }
  return PluginSettingsSnapshot._(
    fields: Map.unmodifiable(fields),
    definitions: Map.unmodifiable(definitions),
    values: Map.unmodifiable(values),
    revisions: Map.unmodifiable(revisions),
  );
}
