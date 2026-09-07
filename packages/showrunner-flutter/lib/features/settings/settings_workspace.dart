import 'package:flutter/material.dart';

import '../../plugins/registry/plugin_registry.dart';
import '../../services/showrunner_data_service.dart';
import 'interface_preferences.dart';

class SettingsWorkspace extends StatefulWidget {
  const SettingsWorkspace({
    super.key,
    required this.preferences,
    required this.registryFuture,
    required this.dataService,
  });

  final FlutterInterfacePreferences preferences;
  final Future<DartPluginRegistry> registryFuture;
  final ShowRunnerDataService dataService;

  @override
  State<SettingsWorkspace> createState() => _SettingsWorkspaceState();
}

class _SettingsWorkspaceState extends State<SettingsWorkspace>
    with SingleTickerProviderStateMixin {
  final _filterController = TextEditingController();
  final _pluginValues = <String, Map<String, dynamic>>{};
  final _controllers = <String, TextEditingController>{};
  final _savingPlugins = <String>{};
  late final Future<void> _pluginSettingsFuture;
  late final TabController _tabController;
  String _filter = '';
  Object? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _pluginSettingsFuture = _loadPluginSettings();
  }

  @override
  void dispose() {
    _filterController.dispose();
    _tabController.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPluginSettings() async {
    final registry = await widget.registryFuture;
    for (final plugin in registry.plugins) {
      if (plugin.settings.isEmpty) continue;
      final values = await widget.dataService.loadPluginSettings(plugin.id);
      _pluginValues[plugin.id] = {
        for (final setting in plugin.settings)
          setting.id: values[setting.id] ?? setting.defaultValue,
      };
      for (final setting in plugin.settings) {
        if (setting.defaultValue is bool) continue;
        final key = '${plugin.id}:${setting.id}';
        _controllers[key] = TextEditingController(
          text: _displaySettingValue(_pluginValues[plugin.id]![setting.id]),
        );
      }
    }
  }

  Future<void> _setValue(String key, bool value) async {
    setState(() => _error = null);
    try {
      await widget.preferences.setValue(key, value);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _reset() async {
    setState(() => _error = null);
    try {
      await widget.preferences.reset();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _setWindowCloseBehavior(WindowCloseBehavior behavior) async {
    setState(() => _error = null);
    try {
      await widget.preferences.setWindowCloseBehavior(behavior);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _enableAll() async {
    setState(() => _error = null);
    try {
      final registry = await widget.registryFuture;
      await widget.preferences.enableAllPlugins(registry);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _savePlugin(DartPluginManifest plugin) async {
    setState(() {
      _error = null;
      _savingPlugins.add(plugin.id);
    });
    try {
      final values = <String, dynamic>{...?_pluginValues[plugin.id]};
      for (final setting in plugin.settings) {
        final controller = _controllers['${plugin.id}:${setting.id}'];
        if (controller != null) {
          values[setting.id] = _parseSettingValue(
            controller.text,
            setting.defaultValue,
          );
        }
      }
      await widget.dataService.savePluginSettings(plugin.id, values);
      _pluginValues[plugin.id] = values;
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _savingPlugins.remove(plugin.id));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.preferences,
    builder: (context, child) {
      final filter = _filter.trim().toLowerCase();
      final definitions = _filteredInterfaceDefinitions(filter);
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Row(
              children: [
                Text(
                  'Settings',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: widget.preferences.isSaving ? null : _reset,
                  icon: const Icon(Icons.restore),
                  label: const Text('Reset interface'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: widget.preferences.isSaving ? null : _enableAll,
                  icon: const Icon(Icons.power_settings_new),
                  label: const Text('Enable all plugins'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: TextField(
              controller: _filterController,
              decoration: const InputDecoration(
                labelText: 'Search all settings',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() => _filter = value);
                if (value.trim().isNotEmpty && _tabController.index != 0) {
                  _tabController.animateTo(0);
                }
              },
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: const Text('Settings error'),
                  subtitle: Text('$_error'),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.search), text: 'All settings'),
                Tab(icon: Icon(Icons.tune), text: 'Interface'),
                Tab(icon: Icon(Icons.extension_outlined), text: 'Plugins'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAllSettingsTab(context, filter, definitions),
                _buildInterfaceTab(context),
                _buildPluginsTab(context, filter),
              ],
            ),
          ),
        ],
      );
    },
  );

  List<InterfacePreferenceDefinition> _filteredInterfaceDefinitions(
    String filter,
  ) => interfacePreferenceDefinitions.where((definition) {
    return filter.isEmpty ||
        '${definition.title} ${definition.description}'.toLowerCase().contains(
          filter,
        );
  }).toList();

  Widget _buildAllSettingsTab(
    BuildContext context,
    String filter,
    List<InterfacePreferenceDefinition> definitions,
  ) {
    final closeMatches =
        filter.isEmpty ||
        'when closing showrunner system tray exits close behavior'.contains(
          filter,
        );
    return _settingsList([
      if (definitions.isNotEmpty) _buildInterfaceCard(context, definitions),
      if (closeMatches) _buildCloseBehaviorCard(context),
      const SizedBox(height: 16),
      _buildPluginSettings(context, filter),
    ]);
  }

  Widget _buildInterfaceTab(BuildContext context) => _settingsList([
    _buildInterfaceCard(context, interfacePreferenceDefinitions),
    const SizedBox(height: 12),
    _buildCloseBehaviorCard(context),
  ]);

  Widget _buildPluginsTab(BuildContext context, String filter) =>
      _settingsList([_buildPluginSettings(context, filter)]);

  Widget _settingsList(List<Widget> children) => ListView(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
    children: children,
  );

  Widget _buildInterfaceCard(
    BuildContext context,
    List<InterfacePreferenceDefinition> definitions,
  ) => Card(
    child: Column(
      children: [
        const ListTile(
          leading: Icon(Icons.tune),
          title: Text('Interface'),
          subtitle: Text('Control the layout and integration catalog.'),
        ),
        const Divider(height: 1),
        for (final definition in definitions)
          SwitchListTile(
            title: Text(definition.title),
            subtitle: Text(definition.description),
            value: widget.preferences.value(definition.key),
            onChanged: widget.preferences.isSaving
                ? null
                : (value) => _setValue(definition.key, value),
          ),
      ],
    ),
  );

  Widget _buildCloseBehaviorCard(BuildContext context) => Card(
    child: ListTile(
      leading: const Icon(Icons.notifications_active_outlined),
      title: const Text('When closing ShowRunner'),
      subtitle: const Text(
        'Choose whether closing hides ShowRunner in the system tray or exits it.',
      ),
      trailing: DropdownButton<WindowCloseBehavior>(
        value: widget.preferences.windowCloseBehavior,
        onChanged: widget.preferences.isSaving
            ? null
            : (behavior) {
                if (behavior != null) _setWindowCloseBehavior(behavior);
              },
        items: [
          for (final behavior in WindowCloseBehavior.values)
            DropdownMenuItem(
              value: behavior,
              child: Text(_windowCloseBehaviorLabel(behavior)),
            ),
        ],
      ),
    ),
  );

  Widget _buildPluginSettings(BuildContext context, String filter) =>
      FutureBuilder<void>(
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
                subtitle: Text('${snapshot.error}'),
              ),
            );
          }
          return FutureBuilder<DartPluginRegistry>(
            future: widget.registryFuture,
            builder: (context, registrySnapshot) {
              final registry = registrySnapshot.data;
              if (registry == null) return const SizedBox.shrink();
              final sections = _buildPluginSections(context, registry, filter);
              return sections.isEmpty
                  ? const ListTile(
                      leading: Icon(Icons.search_off),
                      title: Text('No plugin settings found'),
                      subtitle: Text('Try a different search.'),
                    )
                  : Column(children: sections);
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
            '${plugin.name} ${setting.displayName} ${setting.id}'
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
                    onPressed: _savingPlugins.contains(plugin.id)
                        ? null
                        : () => _savePlugin(plugin),
                    icon: _savingPlugins.contains(plugin.id)
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
    DartSettingDefinition setting,
  ) {
    final values = _pluginValues[plugin.id] ?? const <String, dynamic>{};
    final value = values[setting.id] ?? setting.defaultValue;
    if (setting.defaultValue is bool) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(setting.displayName),
        subtitle: Text(setting.id),
        value: value == true,
        onChanged: _savingPlugins.contains(plugin.id)
            ? null
            : (next) => setState(() => values[setting.id] = next),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: _controllers['${plugin.id}:${setting.id}'],
        obscureText: setting.secret,
        keyboardType: setting.defaultValue is num
            ? TextInputType.number
            : TextInputType.text,
        decoration: InputDecoration(
          labelText: setting.displayName,
          helperText: setting.id,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

String _windowCloseBehaviorLabel(WindowCloseBehavior behavior) =>
    switch (behavior) {
      WindowCloseBehavior.ask => 'Ask every time',
      WindowCloseBehavior.hideToTray => 'Always hide to tray',
      WindowCloseBehavior.alwaysClose => 'Always close',
    };

String _displaySettingValue(dynamic value) {
  if (value is Map || value is List) return value.toString();
  return value?.toString() ?? '';
}

dynamic _parseSettingValue(String text, dynamic defaultValue) {
  if (defaultValue is int) return int.tryParse(text.trim()) ?? defaultValue;
  if (defaultValue is double) {
    return double.tryParse(text.trim()) ?? defaultValue;
  }
  return text;
}
