import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/oauth_token.dart';
import '../../plugins/registry/plugin_registry.dart';
import '../../plugins/runtime/provider_event_workers.dart';
import '../../services/provider_settings_validator.dart';
import '../../persistence/automation_repository.dart';
import '../../services/showrunner_data_service.dart';
import 'plugin_visibility.dart';
import 'plugin_metadata.dart';

class PluginWorkspace extends StatefulWidget {
  const PluginWorkspace({
    super.key,
    required this.dataService,
    required this.registryFuture,
    required this.providerEvents,
    this.selectedPluginId,
  });

  final ShowRunnerDataService dataService;
  final Future<DartPluginRegistry> registryFuture;
  final ProviderEventRuntime providerEvents;
  final String? selectedPluginId;

  @override
  State<PluginWorkspace> createState() => _PluginWorkspaceState();
}

class _PluginWorkspaceState extends State<PluginWorkspace> {
  final _controllers = <String, TextEditingController>{};
  final _settings = <String, Map<String, dynamic>>{};
  bool _loading = true;
  String? _saving;
  Object? _error;
  String _selectedPluginId = 'obs';
  String _detailsTab = 'overview';
  String _detailsFilter = '';

  final _fields = <String, List<String>>{};
  final _definitions = <String, DartSettingDefinition>{};

  @override
  void initState() {
    super.initState();
    if (widget.selectedPluginId != null) {
      _selectedPluginId = widget.selectedPluginId!;
    }
    _load();
  }

  @override
  void didUpdateWidget(covariant PluginWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectedPluginId = widget.selectedPluginId;
    if (selectedPluginId != null && selectedPluginId != _selectedPluginId) {
      setState(() {
        _selectedPluginId = selectedPluginId;
        _detailsTab = 'overview';
        _detailsFilter = '';
      });
    }
  }

  Future<void> _load() async {
    try {
      final registry = await widget.registryFuture;
      for (final plugin in registry.plugins) {
        _fields[plugin.id] = plugin.settings.map((setting) {
          _definitions['${plugin.id}:${setting.id}'] = setting;
          return setting.id;
        }).toList();
      }
      for (final pluginId in _fields.keys) {
        final values = await widget.dataService.loadPluginSettings(pluginId);
        _settings[pluginId] = values;
        for (final field in _fields[pluginId]!) {
          final key = '$pluginId:$field';
          final definition = _definitions[key]!;
          final value = values.containsKey(field)
              ? values[field]
              : definition.defaultValue;
          _controllers[key] = TextEditingController(
            text: _encodeSettingValue(value),
          );
        }
      }
    } catch (error) {
      _error = error;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save(String pluginId) async {
    setState(() {
      _saving = pluginId;
      _error = null;
    });
    try {
      final values = <String, dynamic>{};
      for (final field in _fields[pluginId]!) {
        final definition = _definitions['$pluginId:$field']!;
        final rawValue = _controllers['$pluginId:$field']!.text.trim();
        if (rawValue.isEmpty && definition.defaultValue == null) continue;
        values[field] = _decodeSettingValue(definition, rawValue);
      }
      final validation = validateProviderSettings(pluginId, values);
      if (!validation.isValid) {
        throw ArgumentError(validation.errors.join(' '));
      }
      await widget.dataService.savePluginSettings(pluginId, values);
      _settings[pluginId] = values;
    } catch (error) {
      _error = error;
    }
    if (mounted) setState(() => _saving = null);
  }

  Future<void> _setEnabled(String pluginId, bool enabled) async {
    setState(() => _error = null);
    try {
      final registry = await widget.registryFuture;
      await persistPluginEnabled(
        dataService: widget.dataService,
        registry: registry,
        pluginId: pluginId,
        enabled: enabled,
      );
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _authorize(String pluginId) async {
    setState(() {
      _saving = pluginId;
      _error = null;
    });
    try {
      final clientId = _controllers['$pluginId:clientId']!.text.trim();
      final clientSecret = _controllers['$pluginId:clientSecret']!.text.trim();
      if (clientId.isEmpty || clientSecret.isEmpty) {
        throw ArgumentError(
          'Client ID and client secret are required before authorization.',
        );
      }
      final isYouTube = pluginId == 'youtube';
      final authorizationEndpoint = isYouTube
          ? 'https://accounts.google.com/o/oauth2/v2/auth'
          : 'https://id.twitch.tv/oauth2/authorize';
      final tokenEndpoint = isYouTube
          ? 'https://oauth2.googleapis.com/token'
          : 'https://id.twitch.tv/oauth2/token';
      final scopes = isYouTube
          ? const [
              'https://www.googleapis.com/auth/youtube.readonly',
              'https://www.googleapis.com/auth/youtube.force-ssl',
            ]
          : const ['chat:read', 'chat:edit', 'moderator:manage:banned_users'];
      final token = await OAuthAuthorizationFlow().authorize(
        requestBuilder: (redirectUri) {
          final state = createOAuthState();
          return const OAuthAuthorizationClient().buildRequest(
            authorizationEndpoint: authorizationEndpoint,
            clientId: clientId,
            redirectUri: redirectUri.toString(),
            state: state,
            scopes: scopes,
          );
        },
        openAuthorizationUrl: _openAuthorizationUrl,
        tokenClient: const OAuthTokenClient(),
        tokenEndpoint: tokenEndpoint,
        clientId: clientId,
        clientSecret: clientSecret,
      );
      final values = <String, dynamic>{
        ..._settings[pluginId] ?? <String, dynamic>{},
      };
      values['clientId'] = clientId;
      values['clientSecret'] = clientSecret;
      values['accessToken'] = token.accessToken;
      if (token.refreshToken != null) {
        values['refreshToken'] = token.refreshToken;
      }
      if (token.expiresAt != null) {
        values['expiresAt'] = token.expiresAt!.toIso8601String();
      }
      await widget.dataService.savePluginSettings(pluginId, values);
      _settings[pluginId] = values;
      _controllers['$pluginId:accessToken']!.text = token.accessToken;
    } catch (error) {
      _error = error;
    }
    if (mounted) setState(() => _saving = null);
  }

  Future<void> _openAuthorizationUrl(Uri url) async {
    if (!Platform.isWindows) {
      throw UnsupportedError(
        'OAuth browser launch is currently supported on Windows only.',
      );
    }
    await Process.start('cmd.exe', ['/c', 'start', '', url.toString()]);
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DartPluginRegistry>(
      future: widget.registryFuture,
      builder: (context, snapshot) {
        if (_loading || snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text('Plugin registry error: ${snapshot.error}'),
          );
        }
        final registry = snapshot.data;
        if (registry == null) {
          return const Center(child: Text('Plugin registry is unavailable'));
        }
        final plugins = snapshot.data?.plugins.toList() ?? const [];
        final selected = plugins
            .where((p) => p.id == _selectedPluginId)
            .firstOrNull;
        return ListenableBuilder(
          listenable: registry,
          builder: (context, child) {
            if (selected == null) {
              return const Center(child: Text('Select an integration'));
            }
            final contribution = registry.uiFor(selected.id);
            if (contribution != null) {
              return contribution.build(
                    context: context,
                    dataService: widget.dataService,
                    providerEvents: widget.providerEvents,
                    registryFuture: widget.registryFuture,
                  )
                  as Widget;
            }
            return _buildPluginDetails(context, selected, registry);
          },
        );
      },
    );
  }

  Widget _buildPluginDetails(
    BuildContext context,
    DartPluginManifest plugin,
    DartPluginRegistry registry,
  ) {
    final isProvider = _fields[plugin.id]?.isNotEmpty == true;
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
                  '${setting.displayName} ${setting.id}',
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
                '${action.displayName ?? action.actionId} ${action.actionId}',
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
                '${trigger.displayName} ${trigger.triggerId}',
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
              (state) =>
                  _matchesDetailFilter('${state.displayName} ${state.id}'),
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
              pluginIconFor(plugin.id),
              color: pluginColorFor(plugin.id),
              size: 28,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plugin.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(
                    '${plugin.id}  |  v${plugin.version}',
                    style: const TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Check plugin health',
              onPressed: () async {
                final healthy = await widget.registryFuture.then(
                  (r) => r.checkHealth(plugin.id),
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      healthy
                          ? '${plugin.name} is ready'
                          : '${plugin.name} is unavailable',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.health_and_safety_outlined),
            ),
            Switch(
              value: registry.isPluginEnabled(plugin.id),
              onChanged: (value) => _setEnabled(plugin.id, value),
            ),
          ],
        ),
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
                ? _buildProviderSettings(context, plugin.id)
                : _buildManifestTab(
                    context,
                    title: 'Settings',
                    icon: Icons.settings_outlined,
                    values: plugin.settings
                        .map(
                          (setting) => '${setting.displayName} · ${setting.id}',
                        )
                        .toList(),
                  ),
          'actions' => _buildManifestTab(
            context,
            title: 'Actions',
            icon: Icons.bolt,
            values: plugin.actions
                .map(
                  (action) =>
                      '${action.displayName ?? action.actionId} · ${action.actionId}',
                )
                .toList(),
          ),
          'triggers' => _buildManifestTab(
            context,
            title: 'Triggers',
            icon: Icons.notifications_active_outlined,
            values: plugin.triggers
                .map(
                  (trigger) => '${trigger.displayName} · ${trigger.triggerId}',
                )
                .toList(),
          ),
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
            pluginId: plugin.id,
          ),
        ],
      );

  Widget _buildUsageTab(DartPluginManifest plugin) =>
      _PluginUsageSummary(dataService: widget.dataService, pluginId: plugin.id);

  Widget _buildStateTab(
    BuildContext context,
    DartPluginManifest plugin,
    DartPluginRegistry registry,
  ) {
    final values = registry.stateValues(plugin.id);
    final rows = plugin.states
        .where(
          (state) => _matchesDetailFilter('${state.displayName} ${state.id}'),
        )
        .map(
          (state) => ListTile(
            dense: true,
            title: Text(state.displayName),
            subtitle: Text(state.id),
            trailing: Text(values[state.id]?.toString() ?? 'null'),
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

  Widget _buildProviderSettings(BuildContext context, String selectedPluginId) {
    final fields = _fields[selectedPluginId] ?? const <String>[];
    final visibleFields = fields.where((field) {
      final definition = _definitions['$selectedPluginId:$field'];
      return definition != null &&
          _matchesDetailFilter('${definition.displayName} $field');
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Configure local transports and provider credentials for the Dart runtime.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        if (_error != null) Text('Settings error: $_error'),
        if (visibleFields.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _detailsFilter.trim().isEmpty
                  ? 'No plugin settings registered.'
                  : 'No matches for "${_detailsFilter.trim()}".',
            ),
          )
        else
          Column(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(pluginIconFor(selectedPluginId)),
                          const SizedBox(width: 8),
                          Text(
                            selectedPluginId.toUpperCase(),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const Spacer(),
                          if (selectedPluginId == 'youtube' ||
                              selectedPluginId == 'twitch')
                            OutlinedButton.icon(
                              onPressed: _saving == selectedPluginId
                                  ? null
                                  : () => _authorize(selectedPluginId),
                              icon: const Icon(Icons.login),
                              label: const Text('Authorize'),
                            ),
                          if (selectedPluginId == 'youtube' ||
                              selectedPluginId == 'twitch')
                            const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: _saving == selectedPluginId
                                ? null
                                : () => _save(selectedPluginId),
                            icon: _saving == selectedPluginId
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save),
                            label: const Text('Save'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ...visibleFields.map(
                        (field) => _buildSettingField(selectedPluginId, field),
                      ),
                    ],
                  ),
                ),
              ),
              if (selectedPluginId == 'youtube' || selectedPluginId == 'twitch')
                _OAuthDiagnostics(
                  provider: selectedPluginId,
                  values: _settings[selectedPluginId] ?? const {},
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildSettingField(String pluginId, String field) {
    final key = '$pluginId:$field';
    final definition = _definitions[key]!;
    final controller = _controllers[key]!;
    if (definition.valueType == DartSettingType.boolean) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: CheckboxListTile(
          value: _decodeBoolean(controller.text) ?? false,
          title: Text(definition.displayName),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (value) {
            controller.text = (value ?? false).toString();
            setState(() {});
          },
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        obscureText: definition.secret,
        keyboardType: definition.valueType == DartSettingType.number
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: InputDecoration(
          labelText: definition.displayName,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

String _encodeSettingValue(Object? value) => value?.toString() ?? '';

dynamic _decodeSettingValue(DartSettingDefinition definition, String rawValue) {
  if (definition.valueType == DartSettingType.boolean) {
    return _decodeBoolean(rawValue) ?? definition.defaultValue ?? false;
  }
  if (definition.valueType == DartSettingType.number) {
    final parsed = definition.defaultValue is int
        ? int.tryParse(rawValue)
        : double.tryParse(rawValue);
    if (parsed == null) {
      throw FormatException(
        '${definition.displayName} must be a valid number.',
      );
    }
    return parsed;
  }
  return rawValue;
}

bool? _decodeBoolean(String rawValue) {
  switch (rawValue.trim().toLowerCase()) {
    case 'true':
    case '1':
    case 'yes':
    case 'on':
      return true;
    case 'false':
    case '0':
    case 'no':
    case 'off':
      return false;
    default:
      return null;
  }
}

class _OAuthDiagnostics extends StatelessWidget {
  const _OAuthDiagnostics({required this.provider, required this.values});

  final String provider;
  final Map<String, dynamic> values;

  @override
  Widget build(BuildContext context) {
    final accessToken = values['accessToken']?.toString() ?? '';
    final refreshToken = values['refreshToken']?.toString() ?? '';
    final expiresAt = DateTime.tryParse(values['expiresAt']?.toString() ?? '');
    final expired = expiresAt != null && DateTime.now().isAfter(expiresAt);
    final state = accessToken.isEmpty
        ? 'Not authorized'
        : expired
        ? 'Access token expired; refresh token ${refreshToken.isEmpty ? 'missing' : 'available'}'
        : 'Access token available';
    return Card(
      child: ListTile(
        leading: Icon(
          accessToken.isEmpty || expired ? Icons.warning_amber : Icons.verified,
          color: accessToken.isEmpty || expired ? Colors.amber : Colors.green,
        ),
        title: Text('$provider OAuth diagnostics'),
        subtitle: Text(
          '$state${expiresAt == null ? '' : '\nExpires: $expiresAt'}',
        ),
      ),
    );
  }
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
    final entries = await AutomationRepository.loadDirectory(
      Directory('${widget.dataService.userDirectory.path}/automations'),
    );
    final usage = <String>[];
    for (final entry in entries) {
      final graph = entry.automation?.graph;
      if (graph == null) continue;
      final usesPlugin = graph.nodes.any(
        (node) => node.data['plugin'] == widget.pluginId,
      );
      if (usesPlugin) usage.add(entry.fileName);
    }
    return usage;
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

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
