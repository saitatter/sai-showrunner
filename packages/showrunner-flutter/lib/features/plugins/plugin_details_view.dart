import 'plugin_diagnostic_preview.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_feedback.dart';
import '../../plugins/registry/plugin_registry.dart';
import '../../schema/data_input.dart';
import '../../services/showrunner_data_service.dart';
import 'plugin_metadata.dart';
import 'plugin_usage.dart';

class PluginDetailsView extends StatefulWidget {
  const PluginDetailsView({
    super.key,
    required this.plugin,
    required this.registry,
    required this.dataService,
    required this.onEnabled,
    required this.settingsBuilder,
  });
  final DartPluginManifest plugin;
  final DartPluginRegistry registry;
  final ShowRunnerDataService dataService;
  final ValueChanged<bool> onEnabled;
  final Widget Function(BuildContext context, String filter) settingsBuilder;
  @override
  State<PluginDetailsView> createState() => _PluginDetailsViewState();
}

class _PluginDetailsViewState extends State<PluginDetailsView> {
  String _detailsTab = 'overview', _detailsFilter = '';
  @override
  Widget build(BuildContext context) {
    final plugin = widget.plugin;
    final registry = widget.registry;
    final isProvider = plugin.settings.isNotEmpty;
    final tabs = [
      _PluginDetailsTab('overview', 'Overview', Icons.info_outline),
      _PluginDetailsTab(
        'usage',
        'Usage',
        Icons.account_tree_outlined,
        count: null,
      ),
      if (plugin.settings.isNotEmpty)
        _PluginDetailsTab(
          'settings',
          'Settings',
          Icons.settings_outlined,
          count: plugin.settings
              .where(
                (setting) => _matchesDetailFilter(
                  '${setting.displayName} ${setting.id.value}',
                ),
              )
              .length,
        ),
      _PluginDetailsTab(
        'actions',
        'Actions',
        Icons.bolt,
        count: plugin.actions
            .where(
              (action) => _matchesDetailFilter(
                '${action.displayName ?? action.actionId.value} ${action.actionId.value}',
              ),
            )
            .length,
      ),
      _PluginDetailsTab(
        'triggers',
        'Triggers',
        Icons.notifications_active_outlined,
        count: plugin.triggers
            .where(
              (trigger) => _matchesDetailFilter(
                '${trigger.displayName} ${trigger.triggerId.value}',
              ),
            )
            .length,
      ),
      _PluginDetailsTab(
        'state',
        'State',
        Icons.data_object,
        count: plugin.states
            .where(
              (state) => _matchesDetailFilter(
                '${state.displayName} ${state.id.value}',
              ),
            )
            .length,
      ),
    ];
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Icon(
              pluginIconFor(plugin.id.value),
              color: pluginColorFor(plugin.id.value),
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'INTEGRATION PLUGIN',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                  Text(
                    plugin.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    '${plugin.id.value}  |  v${plugin.version}',
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Check plugin health',
              onPressed: () async {
                final health = await widget.registry.checkHealthDetailsId(
                  plugin.id,
                );
                if (!context.mounted) return;
                showShowRunnerFeedback(
                  context,
                  health.isHealthy
                      ? '${plugin.name} is ready'
                      : '${plugin.name}: ${health.status.name}. Check connection settings and retry.',
                  severity: health.isHealthy
                      ? ShowRunnerFeedbackSeverity.success
                      : ShowRunnerFeedbackSeverity.warning,
                );
              },
              icon: const Icon(Icons.health_and_safety_outlined),
            ),
            Switch(
              value: registry.isPluginEnabledId(plugin.id),
              onChanged: (value) => widget.onEnabled(value),
            ),
          ],
        ),
        if (pluginDescriptionFor(plugin.id.value).trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(pluginDescriptionFor(plugin.id.value)),
        ],
        const SizedBox(height: 20),
        TextField(
          decoration: const InputDecoration(
            labelText: 'Search integration details',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => setState(() => _detailsFilter = value),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final tab in tabs)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    selected: _detailsTab == tab.id,
                    avatar: Icon(tab.icon, size: 16),
                    label: Text(
                      tab.count == null
                          ? tab.label
                          : '${tab.label} ${tab.count}',
                    ),
                    onSelected: (_) => setState(() => _detailsTab = tab.id),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        switch (_detailsTab) {
          'usage' => _buildUsageTab(plugin),
          'settings' =>
            isProvider
                ? widget.settingsBuilder(context, _detailsFilter)
                : _buildManifestTab(
                    context,
                    title: 'Settings',
                    icon: Icons.settings_outlined,
                    values: plugin.settings
                        .map(
                          (setting) =>
                              '${setting.displayName} · ${setting.id.value}',
                        )
                        .toList(),
                  ),
          'actions' => _buildActionTab(context, plugin),
          'triggers' => _buildTriggerTab(context, plugin),
          'state' => _buildStateTab(context, plugin, registry),
          _ => _buildOverviewTab(context, plugin),
        },
      ],
    );
  }

  Widget _buildOverviewTab(BuildContext context, DartPluginManifest plugin) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Overview', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Flutter runtime integration registered for ${plugin.name}.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _PluginStat(value: plugin.actions.length, label: 'actions'),
              _PluginStat(value: plugin.triggers.length, label: 'triggers'),
              _PluginStat(value: plugin.settings.length, label: 'settings'),
              _PluginStat(value: plugin.states.length, label: 'state values'),
            ],
          ),
          const SizedBox(height: 12),
          _PluginUsageSummary(
            dataService: widget.dataService,
            pluginId: plugin.id.value,
          ),
        ],
      );

  Widget _buildUsageTab(DartPluginManifest plugin) => _PluginUsageDetails(
    dataService: widget.dataService,
    pluginId: plugin.id.value,
    filter: _detailsFilter,
    registry: widget.registry,
  );

  Widget _buildStateTab(
    BuildContext context,
    DartPluginManifest plugin,
    DartPluginRegistry registry,
  ) {
    final values = registry.stateValues(plugin.id.value);
    final rows = plugin.states
        .where(
          (state) =>
              _matchesDetailFilter('${state.displayName} ${state.id.value}'),
        )
        .map(
          (state) => ListTile(
            dense: true,
            title: Text(state.displayName),
            subtitle: Text(state.id.value),
            trailing: Text(values[state.id.value]?.toString() ?? 'null'),
          ),
        )
        .toList();
    return _buildRowsCard(
      context,
      title: 'State',
      icon: Icons.data_object,
      rows: rows,
      emptyLabel: 'No runtime state registered',
    );
  }

  Widget _buildManifestTab(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<String> values,
  }) {
    final rows = values
        .where(_matchesDetailFilter)
        .map((value) => ListTile(dense: true, title: Text(value)))
        .toList();
    return _buildRowsCard(
      context,
      title: title,
      icon: icon,
      rows: rows,
      emptyLabel: _detailsFilter.trim().isEmpty
          ? 'Nothing registered yet'
          : 'No matches for "${_detailsFilter.trim()}".',
    );
  }

  Widget _buildActionTab(BuildContext context, DartPluginManifest plugin) {
    final rows = plugin.actions
        .where(
          (action) => _matchesDetailFilter(
            '${action.displayName ?? action.actionId.value} ${action.actionId.value}',
          ),
        )
        .map(
          (action) => ListTile(
            dense: true,
            leading: const Icon(Icons.bolt),
            title: Text(action.displayName ?? action.actionId.value),
            subtitle: Text(
              '${action.actionId.value}\n'
              'Config: ${_schemaSummary(action.configSchema)}\n'
              'Result: ${_schemaSummary(action.resultSchema)}',
            ),
          ),
        )
        .toList();
    return _buildRowsCard(
      context,
      title: 'Actions',
      icon: Icons.bolt,
      rows: rows,
      emptyLabel: _detailsFilter.trim().isEmpty
          ? 'Nothing registered yet'
          : 'No matches for "${_detailsFilter.trim()}".',
    );
  }

  Widget _buildTriggerTab(BuildContext context, DartPluginManifest plugin) {
    final rows = plugin.triggers
        .where(
          (trigger) => _matchesDetailFilter(
            '${trigger.displayName} ${trigger.triggerId.value}',
          ),
        )
        .map(
          (trigger) => ListTile(
            dense: true,
            leading: const Icon(Icons.notifications_active_outlined),
            title: Text(trigger.displayName),
            subtitle: Text(
              '${trigger.triggerId.value}\n'
              'Config: ${_schemaSummary(trigger.configSchema)}',
            ),
          ),
        )
        .toList();
    return _buildRowsCard(
      context,
      title: 'Triggers',
      icon: Icons.notifications_active_outlined,
      rows: rows,
      emptyLabel: _detailsFilter.trim().isEmpty
          ? 'Nothing registered yet'
          : 'No matches for "${_detailsFilter.trim()}".',
    );
  }

  Widget _buildRowsCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> rows,
    required String emptyLabel,
  }) => Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text('${rows.length} visible'),
        ),
        if (rows.isEmpty)
          ListTile(dense: true, title: Text(emptyLabel))
        else
          ...rows,
      ],
    ),
  );

  bool _matchesDetailFilter(String value) {
    final query = _detailsFilter.trim().toLowerCase();
    return query.isEmpty || value.toLowerCase().contains(query);
  }
}

String _schemaSummary(DartDataInputSchema? schema) {
  if (schema == null) return 'none';
  if (schema.kind != DartDataInputKind.object) {
    return '${schema.label}: ${_schemaTypeName(schema)}';
  }
  if (schema.fields.isEmpty) return 'none';
  return schema.fields
      .map((field) {
        final required = field.required ? ', required' : '';
        return '${field.label}: ${_schemaTypeName(field)}$required';
      })
      .join(', ');
}

String _schemaTypeName(DartDataInputSchema schema) {
  if (schema.kind == DartDataInputKind.resource &&
      schema.resourceType?.value.isNotEmpty == true) {
    return 'resource<${schema.resourceType}>';
  }
  return switch (schema.kind) {
    DartDataInputKind.multilineText => 'text',
    DartDataInputKind.filePath => 'file',
    DartDataInputKind.lightColor => 'light color',
    DartDataInputKind.obsTransform => 'OBS transform',
    DartDataInputKind.keyboardKey => 'keyboard key',
    DartDataInputKind.keyCombo => 'key combo',
    DartDataInputKind.array => 'array',
    DartDataInputKind.object => 'object',
    DartDataInputKind.enumeration => 'enum',
    _ => schema.kind.name,
  };
}

class _PluginDetailsTab {
  const _PluginDetailsTab(this.id, this.label, this.icon, {this.count});

  final String id;
  final String label;
  final IconData icon;
  final int? count;
}

class _PluginStat extends StatelessWidget {
  const _PluginStat({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$value', style: Theme.of(context).textTheme.headlineSmall),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );
}

class _PluginUsageSummary extends StatefulWidget {
  const _PluginUsageSummary({
    required this.dataService,
    required this.pluginId,
  });

  final ShowRunnerDataService dataService;
  final String pluginId;

  @override
  State<_PluginUsageSummary> createState() => _PluginUsageSummaryState();
}

class _PluginUsageSummaryState extends State<_PluginUsageSummary> {
  late Future<List<String>> _usageFuture;

  @override
  void initState() {
    super.initState();
    _usageFuture = _loadUsage();
  }

  @override
  void didUpdateWidget(covariant _PluginUsageSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataService != widget.dataService ||
        oldWidget.pluginId != widget.pluginId) {
      _usageFuture = _loadUsage();
    }
  }

  Future<List<String>> _loadUsage() async {
    final usage = await loadPluginUsage(
      loadEntries: widget.dataService.storage.listAutomations,
      pluginId: widget.pluginId,
    );
    return usage.map((entry) => entry.automationFile).toSet().toList()..sort();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<String>>(
    future: _usageFuture,
    builder: (context, snapshot) {
      final usage = snapshot.data ?? const <String>[];
      return Card(
        child: ListTile(
          leading: const Icon(Icons.account_tree_outlined),
          title: const Text('Automation usage'),
          subtitle: snapshot.connectionState == ConnectionState.waiting
              ? const Text('Scanning saved automations...')
              : Text(
                  usage.isEmpty
                      ? 'Not used in saved automations'
                      : '${usage.length} automation${usage.length == 1 ? '' : 's'}: ${usage.join(', ')}',
                ),
        ),
      );
    },
  );
}

final class _PluginUsageDetails extends StatefulWidget {
  const _PluginUsageDetails({
    required this.dataService,
    required this.pluginId,
    required this.filter,
    required this.registry,
  });

  final ShowRunnerDataService dataService;
  final String pluginId;
  final String filter;
  final DartPluginRegistry registry;

  @override
  State<_PluginUsageDetails> createState() => _PluginUsageDetailsState();
}

final class _PluginUsageDetailsState extends State<_PluginUsageDetails> {
  late Future<List<PluginUsageEntry>> _usageFuture;

  @override
  void initState() {
    super.initState();
    _usageFuture = _load();
  }

  @override
  void didUpdateWidget(covariant _PluginUsageDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataService != widget.dataService ||
        oldWidget.pluginId != widget.pluginId) {
      _usageFuture = _load();
    }
  }

  Future<List<PluginUsageEntry>> _load() => loadPluginUsage(
    loadEntries: widget.dataService.storage.listAutomations,
    pluginId: widget.pluginId,
  );

  Iterable<DartDataInputSchema> _schemas(String contract) sync* {
    final plugin = widget.registry.plugins
        .where((item) => item.id.value == widget.pluginId)
        .firstOrNull;
    if (plugin == null) return;
    for (final action in plugin.actions) {
      if (action.actionId.value == contract && action.configSchema != null) {
        yield action.configSchema!;
      }
    }
    for (final trigger in plugin.triggers) {
      if (trigger.triggerId.value == contract && trigger.configSchema != null) {
        yield trigger.configSchema!;
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<PluginUsageEntry>>(
    future: _usageFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Card(
          child: ListTile(title: Text('Scanning saved automations...')),
        );
      }
      if (snapshot.hasError) {
        return Card(
          child: ListTile(title: Text('Usage error: ${snapshot.error}')),
        );
      }
      final query = widget.filter.trim().toLowerCase();
      final usage = (snapshot.data ?? const <PluginUsageEntry>[]).where((
        entry,
      ) {
        if (query.isEmpty) return true;
        return '${entry.automationName} ${entry.kind} ${entry.name} '
                '${entry.automationFile} ${entry.config}'
            .toLowerCase()
            .contains(query);
      }).toList();
      return Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ListTile(
              leading: Icon(Icons.account_tree_outlined),
              title: Text('Used in automations'),
            ),
            if (usage.isEmpty)
              ListTile(
                dense: true,
                title: Text(
                  query.isEmpty
                      ? 'No current automations use this plugin.'
                      : 'No matches for "${widget.filter.trim()}".',
                ),
              )
            else
              for (final entry in usage)
                ListTile(
                  dense: true,
                  title: Text(entry.automationName),
                  subtitle: Text(
                    '${entry.kind} · ${entry.name} · ${entry.automationFile}'
                    '${entry.config.isEmpty ? '' : '\n${safePluginConfigPreview(entry.config, _schemas(entry.name))}'}',
                  ),
                ),
          ],
        ),
      );
    },
  );
}
