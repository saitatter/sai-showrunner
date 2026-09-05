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
import 'plugin_catalog_filter.dart';

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
      _selectedPluginId = selectedPluginId;
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
          _controllers[key] = TextEditingController(
            text: values[field]?.toString() ?? '',
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
        final value = _controllers['$pluginId:$field']!.text.trim();
        if (value.isEmpty) continue;
        values[field] = field == 'port' ? int.tryParse(value) ?? value : value;
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
          builder: (context, child) => Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 250,
                child: _PluginCatalog(
                  plugins: plugins,
                  selectedId: selected?.id,
                  registry: registry,
                  onSelected: (id) => setState(() => _selectedPluginId = id),
                  onEnabledChanged: _setEnabled,
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: selected == null
                    ? const Center(child: Text('Select a plugin'))
                    : selected.workspaceBuilder != null
                    ? selected.workspaceBuilder!(
                        context,
                        widget.dataService,
                        widget.providerEvents,
                        widget.registryFuture,
                      )
                    : _buildPluginDetails(context, selected, registry),
              ),
            ],
          ),
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
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Icon(
              _pluginIcon(plugin.id),
              color: _pluginColor(plugin.id),
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
        const SizedBox(height: 24),
        _PluginUsageSummary(
          dataService: widget.dataService,
          pluginId: plugin.id,
        ),
        _PluginRuntimeState(
          registryFuture: widget.registryFuture,
          plugin: plugin,
        ),
        const SizedBox(height: 12),
        if (isProvider) ...[
          Text('Settings', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          _buildProviderSettings(context, plugin.id),
        ] else ...[
          _ManifestSection(
            title: 'Actions',
            icon: Icons.bolt,
            values: plugin.actions
                .map((a) => a.displayName ?? a.actionId)
                .toList(),
          ),
          _ManifestSection(
            title: 'Triggers',
            icon: Icons.notifications_active_outlined,
            values: plugin.triggers.map((t) => t.displayName).toList(),
          ),
          _ManifestSection(
            title: 'Settings',
            icon: Icons.settings_outlined,
            values: plugin.settings.map((s) => s.displayName).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildProviderSettings(BuildContext context, String selectedPluginId) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Configure local transports and provider credentials for the Dart runtime.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        if (_error != null) Text('Settings error: $_error'),
        ...[
          _fields.entries.firstWhere((entry) => entry.key == selectedPluginId),
        ].map(
          (entry) => Column(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(entry.key == 'obs' ? Icons.tv : Icons.live_tv),
                          const SizedBox(width: 8),
                          Text(
                            entry.key.toUpperCase(),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const Spacer(),
                          if (entry.key == 'youtube' || entry.key == 'twitch')
                            OutlinedButton.icon(
                              onPressed: _saving == entry.key
                                  ? null
                                  : () => _authorize(entry.key),
                              icon: const Icon(Icons.login),
                              label: const Text('Authorize'),
                            ),
                          if (entry.key == 'youtube' || entry.key == 'twitch')
                            const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: _saving == entry.key
                                ? null
                                : () => _save(entry.key),
                            icon: _saving == entry.key
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
                      ...entry.value.map(
                        (field) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: TextField(
                            controller: _controllers['${entry.key}:$field'],
                            obscureText:
                                _definitions['${entry.key}:$field']?.secret ??
                                false,
                            keyboardType: field == 'port'
                                ? TextInputType.number
                                : TextInputType.text,
                            decoration: InputDecoration(
                              labelText:
                                  _definitions['${entry.key}:$field']
                                      ?.displayName ??
                                  field,
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (entry.key == 'youtube' || entry.key == 'twitch')
                _OAuthDiagnostics(
                  provider: entry.key,
                  values: _settings[entry.key] ?? const {},
                ),
            ],
          ),
        ),
      ],
    );
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

class _PluginCatalog extends StatefulWidget {
  const _PluginCatalog({
    required this.plugins,
    required this.selectedId,
    required this.registry,
    required this.onSelected,
    required this.onEnabledChanged,
  });

  final List<DartPluginManifest> plugins;
  final String? selectedId;
  final DartPluginRegistry registry;
  final ValueChanged<String> onSelected;
  final Future<void> Function(String pluginId, bool enabled) onEnabledChanged;

  @override
  State<_PluginCatalog> createState() => _PluginCatalogState();
}

class _PluginCatalogState extends State<_PluginCatalog> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = filterPlugins(widget.plugins, _query);
    final core = filtered.where((plugin) => plugin.id == 'obs').toList();
    final platforms = filtered.where((plugin) => plugin.id != 'obs').toList();
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 20),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18),
          child: Text(
            'PLUGINS',
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.2,
              color: Colors.white54,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Search plugins',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear plugin search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                      icon: const Icon(Icons.clear),
                    ),
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Text(
              _query.trim().isEmpty
                  ? 'No plugins are registered.'
                  : 'No plugins match “${_query.trim()}”.',
            ),
          ),
        _PluginGroup(
          title: 'Core integrations',
          plugins: core,
          selectedId: widget.selectedId,
          registry: widget.registry,
          onSelected: widget.onSelected,
          onEnabledChanged: widget.onEnabledChanged,
        ),
        _PluginGroup(
          title: 'Platforms',
          plugins: platforms,
          selectedId: widget.selectedId,
          registry: widget.registry,
          onSelected: widget.onSelected,
          onEnabledChanged: widget.onEnabledChanged,
        ),
      ],
    );
  }
}

class _PluginGroup extends StatelessWidget {
  const _PluginGroup({
    required this.title,
    required this.plugins,
    required this.selectedId,
    required this.registry,
    required this.onSelected,
    required this.onEnabledChanged,
  });

  final String title;
  final List<DartPluginManifest> plugins;
  final String? selectedId;
  final DartPluginRegistry registry;
  final ValueChanged<String> onSelected;
  final Future<void> Function(String pluginId, bool enabled) onEnabledChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 12, 6),
        child: Text(
          title,
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
      ),
      ...plugins.map(
        (plugin) => ListTile(
          dense: true,
          selected: plugin.id == selectedId,
          leading: Icon(
            _pluginIcon(plugin.id),
            color: _pluginColor(plugin.id),
            size: 20,
          ),
          title: Text(plugin.name),
          subtitle: Text(
            '${plugin.actions.length} actions  |  ${plugin.triggers.length} triggers',
          ),
          onTap: () => onSelected(plugin.id),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Switch(
                value: registry.isPluginEnabled(plugin.id),
                onChanged: (value) => onEnabledChanged(plugin.id, value),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _ManifestSection extends StatelessWidget {
  const _ManifestSection({
    required this.title,
    required this.icon,
    required this.values,
  });

  final String title;
  final IconData icon;
  final List<String> values;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: ExpansionTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text('${values.length} registered'),
      children: values.isEmpty
          ? [const ListTile(title: Text('Nothing registered yet'))]
          : values
                .map((value) => ListTile(dense: true, title: Text(value)))
                .toList(),
    ),
  );
}

class _PluginUsageSummary extends StatelessWidget {
  const _PluginUsageSummary({
    required this.dataService,
    required this.pluginId,
  });

  final ShowRunnerDataService dataService;
  final String pluginId;

  Future<List<String>> _loadUsage() async {
    final entries = await AutomationRepository.loadDirectory(
      Directory('${dataService.userDirectory.path}/automations'),
    );
    final usage = <String>[];
    for (final entry in entries) {
      final graph = entry.automation?.graph;
      if (graph == null) continue;
      final usesPlugin = graph.nodes.any(
        (node) => node.data['plugin'] == pluginId,
      );
      if (usesPlugin) usage.add(entry.fileName);
    }
    return usage;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<String>>(
    future: _loadUsage(),
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

class _PluginRuntimeState extends StatelessWidget {
  const _PluginRuntimeState({
    required this.registryFuture,
    required this.plugin,
  });

  final Future<DartPluginRegistry> registryFuture;
  final DartPluginManifest plugin;

  @override
  Widget build(BuildContext context) => FutureBuilder<DartPluginRegistry>(
    future: registryFuture,
    builder: (context, snapshot) {
      final registry = snapshot.data;
      if (registry == null) return _buildCard(context, null);
      return ListenableBuilder(
        listenable: registry,
        builder: (context, _) => _buildCard(context, registry),
      );
    },
  );

  Widget _buildCard(BuildContext context, DartPluginRegistry? registry) {
    final values = registry?.stateValues(plugin.id) ?? const {};
    final rows = plugin.states.map(
      (state) => ListTile(
        dense: true,
        title: Text(state.displayName),
        subtitle: Text(state.id),
        trailing: Text(values[state.id]?.toString() ?? 'null'),
      ),
    );
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.monitor_heart_outlined),
        title: const Text('Runtime state'),
        subtitle: Text('${plugin.states.length} registered values'),
        children: rows.isEmpty
            ? [const ListTile(title: Text('No runtime state registered'))]
            : rows.toList(),
      ),
    );
  }
}

IconData _pluginIcon(String id) => switch (id) {
  'obs' => Icons.tv,
  'youtube' => Icons.smart_display,
  'twitch' => Icons.live_tv,
  _ => Icons.extension,
};

Color _pluginColor(String id) => switch (id) {
  'obs' => const Color(0xff8b9bb4),
  'youtube' => const Color(0xffff5f56),
  'twitch' => const Color(0xffa970ff),
  _ => const Color(0xff2dd4bf),
};

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
