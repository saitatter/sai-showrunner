import 'package:flutter/material.dart';
import '../../plugins/registry/plugin_registry.dart';
import '../../services/showrunner_data_service.dart';
import '../../persistence/document_revision.dart';
import '../plugins/plugin_settings_snapshot.dart';
import '../plugins/plugin_setting_value.dart';
import '../plugins/plugin_setting_text_field.dart';

class PluginPreferencesPanel extends StatefulWidget {
  const PluginPreferencesPanel({
    super.key,
    required this.dataService,
    required this.registryFuture,
    required this.filter,
  });
  final ShowRunnerDataService dataService;
  final Future<DartPluginRegistry> registryFuture;
  final String filter;
  @override
  State<PluginPreferencesPanel> createState() => _PluginPreferencesPanelState();
}

class _PluginPreferencesPanelState extends State<PluginPreferencesPanel> {
  final _pluginValues = <String, Map<String, dynamic>>{};
  final _storageRevisions = <String, DocumentRevision>{};
  final _controllers = <String, TextEditingController>{};
  final _savingPlugins = <String>{};
  late Future<void> _pluginSettingsFuture;
  Object _owner = Object();
  bool _saveFailed = false;
  @override
  void initState() {
    super.initState();
    _pluginSettingsFuture = _loadPluginSettings();
  }

  @override
  void didUpdateWidget(PluginPreferencesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.registryFuture != widget.registryFuture ||
        oldWidget.dataService.userDirectory.absolute.path !=
            widget.dataService.userDirectory.absolute.path) {
      _owner = Object();
      _savingPlugins.clear();
      _saveFailed = false;
      _pluginSettingsFuture = _loadPluginSettings();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPluginSettings() async {
    final owner = _owner;
    final snapshot = await loadPluginSettingsSnapshot(
      registryFuture: widget.registryFuture,
      read: widget.dataService.loadPluginSettings,
    );
    if (!mounted || !identical(owner, _owner)) return;
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    _pluginValues.clear();
    _storageRevisions
      ..clear()
      ..addAll(snapshot.revisions);
    for (final entry in snapshot.values.entries) {
      _pluginValues[entry.key] = Map<String, dynamic>.from(entry.value);
    }
    for (final entry in snapshot.fields.entries) {
      for (final field in entry.value) {
        final key = '${entry.key}:$field';
        final definition = snapshot.definitions[key]!;
        final values = _pluginValues[entry.key]!;
        values.putIfAbsent(field, () => definition.defaultValue);
        if (definition.valueType == DartSettingType.boolean) continue;
        _controllers[key] = TextEditingController(
          text: encodePluginSettingValue(values[field]),
        );
      }
    }
  }

  Future<void> _savePlugin(DartPluginManifest plugin) async {
    final owner = _owner;
    final data = widget.dataService;
    setState(() {
      _saveFailed = false;
      _savingPlugins.add(plugin.id.value);
    });
    try {
      final values = <String, dynamic>{...?_pluginValues[plugin.id.value]};
      for (final setting in plugin.settings) {
        final controller =
            _controllers['${plugin.id.value}:${setting.id.value}'];
        if (controller != null) {
          values[setting.id.value] = decodePluginSettingValue(
            setting,
            controller.text.trim(),
          );
        }
      }
      await data.savePluginSettings(
        plugin.id.value,
        values,
        expectedRevision: _storageRevisions[plugin.id.value],
      );
      if (!mounted || !identical(owner, _owner)) return;
      _storageRevisions[plugin.id.value] = DocumentRevision.of(values);
      _pluginValues[plugin.id.value] = values;
    } catch (error) {
      if (mounted && identical(owner, _owner)) {
        setState(() => _saveFailed = true);
      }
    } finally {
      if (mounted && identical(owner, _owner)) {
        setState(() => _savingPlugins.remove(plugin.id.value));
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _pluginSettingsFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: ListTile(
            leading: const Icon(Icons.error_outline),
            title: const Text('Plugin settings unavailable'),
            subtitle: const Text(
              'Plugin settings could not be loaded. Check storage access and retry.',
            ),
          ),
        );
      }
      return FutureBuilder<DartPluginRegistry>(
        future: widget.registryFuture,
        builder: (context, registrySnapshot) {
          final registry = registrySnapshot.data;
          if (registry == null) return const SizedBox.shrink();
          final sections = _buildPluginSections(
            context,
            registry,
            widget.filter,
          );
          return sections.isEmpty
              ? const ListTile(
                  leading: Icon(Icons.search_off),
                  title: Text('No plugin settings found'),
                  subtitle: Text('Try a different search.'),
                )
              : Column(
                  children: [
                    if (_saveFailed)
                      const Text(
                        'Plugin settings could not be saved. Check the fields and storage access, then retry.',
                      ),
                    ...sections,
                  ],
                );
        },
      );
    },
  );

  List<Widget> _buildPluginSections(
    BuildContext context,
    DartPluginRegistry registry,
    String filter,
  ) {
    final sections = <Widget>[];
    for (final plugin in registry.plugins) {
      final settings = plugin.settings.where((setting) {
        return filter.isEmpty ||
            '${plugin.name} ${setting.displayName} ${setting.id.value}'
                .toLowerCase()
                .contains(filter);
      }).toList();
      if (settings.isEmpty) continue;
      sections.add(
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.extension_outlined),
                  title: Text(plugin.name),
                  subtitle: Text('${settings.length} settings'),
                ),
                for (final setting in settings)
                  _buildPluginSetting(context, plugin, setting),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _savingPlugins.contains(plugin.id.value)
                        ? null
                        : () => _savePlugin(plugin),
                    icon: _savingPlugins.contains(plugin.id.value)
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: const Text('Save plugin settings'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return sections;
  }

  Widget _buildPluginSetting(
    BuildContext context,
    DartPluginManifest plugin,
    DartSettingContract setting,
  ) {
    final values = _pluginValues[plugin.id.value] ?? const <String, dynamic>{};
    final value = values[setting.id.value] ?? setting.defaultValue;
    if (setting.valueType == DartSettingType.boolean) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(setting.displayName),
        subtitle: Text(setting.id.value),
        value: value == true,
        onChanged: _savingPlugins.contains(plugin.id.value)
            ? null
            : (next) => setState(() => values[setting.id.value] = next),
      );
    }
    return PluginSettingTextField(
      definition: setting,
      controller: _controllers['${plugin.id.value}:${setting.id.value}']!,
      showId: true,
      enabled: !_savingPlugins.contains(plugin.id.value),
    );
  }
}
