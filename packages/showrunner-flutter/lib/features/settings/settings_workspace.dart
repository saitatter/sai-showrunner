import 'plugin_preferences_panel.dart';
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
  late final TabController _tabController;
  String _filter = '';
  Object? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _filterController.dispose();
    _tabController.dispose();
    super.dispose();
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
                  subtitle: const Text(
                    'Settings could not be updated. Check storage access and retry.',
                  ),
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
      PluginPreferencesPanel(
        dataService: widget.dataService,
        registryFuture: widget.registryFuture,
        filter: filter,
      ),
    ]);
  }

  Widget _buildInterfaceTab(BuildContext context) => _settingsList([
    _buildInterfaceCard(context, interfacePreferenceDefinitions),
    const SizedBox(height: 12),
    _buildCloseBehaviorCard(context),
  ]);

  Widget _buildPluginsTab(BuildContext context, String filter) =>
      _settingsList([
        PluginPreferencesPanel(
          dataService: widget.dataService,
          registryFuture: widget.registryFuture,
          filter: filter,
        ),
      ]);

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
}

String _windowCloseBehaviorLabel(WindowCloseBehavior behavior) =>
    switch (behavior) {
      WindowCloseBehavior.ask => 'Ask every time',
      WindowCloseBehavior.hideToTray => 'Always hide to tray',
      WindowCloseBehavior.alwaysClose => 'Always close',
    };
