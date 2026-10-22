import 'plugin_setting_value.dart';
import 'plugin_setting_text_field.dart';
import 'plugin_details_view.dart';
import 'plugin_settings_snapshot.dart';
import '../../design_system/workspace_notice.dart';
import '../../plugins/youtube/auth_service.dart';
import '../../persistence/document_revision.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/commands/app_command.dart';
import '../../app/workspace_registry.dart';
import '../../plugins/registry/plugin_registry.dart';
import '../../plugins/registry/flutter_plugin_ui_contract.dart';
import '../../plugins/philips_hue/discovery.dart';
import '../../plugins/runtime/provider_event_workers.dart';
import '../../plugins/twitch/account_runtime.dart';
import '../../services/provider_settings_validator.dart';
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
    this.forceGenericDetails = false,
    this.commands,
    this.onOpenWorkspace,
  });

  final ShowRunnerDataService dataService;
  final Future<DartPluginRegistry> registryFuture;
  final ProviderEventRuntime providerEvents;
  final String? selectedPluginId;
  final bool forceGenericDetails;
  final AppCommandRegistry? commands;
  final ValueChanged<WorkspaceId>? onOpenWorkspace;

  @override
  State<PluginWorkspace> createState() => _PluginWorkspaceState();
}

class _PluginWorkspaceState extends State<PluginWorkspace> {
  final _controllers = <String, TextEditingController>{};
  final _settings = <String, Map<String, dynamic>>{};
  final _storageRevisions = <String, DocumentRevision>{};
  bool _loading = true;
  bool _loadFailed = false;
  String? _saving;
  Object? _error;
  bool _huePairing = false;
  bool _huePaired = false;
  String _selectedPluginId = 'obs';
  Object _loadOwner = Object();

  final _fields = <String, List<String>>{};
  final _definitions = <String, DartSettingContract>{};

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
    if (oldWidget.registryFuture != widget.registryFuture ||
        oldWidget.dataService.userDirectory.absolute.path !=
            widget.dataService.userDirectory.absolute.path) {
      _loadOwner = Object();
      _loading = true;
      _saving = null;
      _error = null;
      _load();
    }
    final selectedPluginId = widget.selectedPluginId;
    if (selectedPluginId != null && selectedPluginId != _selectedPluginId) {
      setState(() {
        _selectedPluginId = selectedPluginId;
      });
    }
  }

  Future<void> _load() async {
    final owner = _loadOwner;
    final data = widget.dataService;
    try {
      final snapshot = await loadPluginSettingsSnapshot(
        registryFuture: widget.registryFuture,
        read: data.loadPluginSettings,
      );
      if (!mounted || !identical(owner, _loadOwner)) return;
      for (final controller in _controllers.values) {
        controller.dispose();
      }
      _controllers.clear();
      _fields
        ..clear()
        ..addAll(snapshot.fields);
      _definitions
        ..clear()
        ..addAll(snapshot.definitions);
      _settings
        ..clear()
        ..addAll({
          for (final entry in snapshot.values.entries)
            entry.key: Map<String, dynamic>.from(entry.value),
        });
      _storageRevisions
        ..clear()
        ..addAll(snapshot.revisions);
      for (final entry in _fields.entries) {
        for (final field in entry.value) {
          final key = '${entry.key}:$field';
          final definition = _definitions[key]!;
          final values = _settings[entry.key]!;
          _controllers[key] = TextEditingController(
            text: encodePluginSettingValue(
              values.containsKey(field)
                  ? values[field]
                  : definition.defaultValue,
            ),
          );
        }
      }
      _error = null;
      _loadFailed = false;
    } catch (error) {
      if (!mounted || !identical(owner, _loadOwner)) return;
      _error = error;
      _loadFailed = true;
    }
    if (mounted && identical(owner, _loadOwner)) {
      setState(() => _loading = false);
    }
  }

  Future<void> _save(String pluginId) async {
    final owner = _loadOwner;
    final dataService = widget.dataService;
    setState(() {
      _saving = pluginId;
      _error = null;
    });
    try {
      final values = <String, dynamic>{...?_settings[pluginId]};
      for (final field in _fields[pluginId]!) {
        final definition = _definitions['$pluginId:$field']!;
        final rawValue = _controllers['$pluginId:$field']!.text.trim();
        if (rawValue.isEmpty && definition.defaultValue == null) continue;
        values[field] = decodePluginSettingValue(definition, rawValue);
      }
      final validation = validateProviderSettings(pluginId, values);
      if (!validation.isValid) {
        throw ArgumentError(validation.errors.join(' '));
      }
      await dataService.savePluginSettings(
        pluginId,
        values,
        expectedRevision: _storageRevisions[pluginId],
      );
      if (!mounted || !identical(owner, _loadOwner)) return;
      _storageRevisions[pluginId] = DocumentRevision.of(values);
      _settings[pluginId] = values;
    } catch (error) {
      if (!mounted || !identical(owner, _loadOwner)) return;
      _error = error;
    }
    if (mounted && identical(owner, _loadOwner)) setState(() => _saving = null);
  }

  Future<void> _setEnabled(String pluginId, bool enabled) async {
    final owner = _loadOwner;
    final dataService = widget.dataService;
    setState(() => _error = null);
    try {
      final registry = await widget.registryFuture;
      if (!mounted || !identical(owner, _loadOwner)) return;
      await persistPluginEnabled(
        dataService: dataService,
        registry: registry,
        pluginId: pluginId,
        enabled: enabled,
      );
    } catch (error) {
      if (mounted && identical(owner, _loadOwner)) {
        setState(() => _error = error);
      }
    }
  }

  Future<void> _authorize(String pluginId) async {
    final owner = _loadOwner;
    final dataService = widget.dataService;
    setState(() {
      _saving = pluginId;
      _error = null;
    });
    try {
      final clientId = _controllers['$pluginId:clientId']!.text.trim();
      final clientSecret = _controllers['$pluginId:clientSecret']!.text.trim();
      if (pluginId == 'twitch') {
        if (clientId.isEmpty) {
          throw ArgumentError(
            'Client ID is required before Twitch authorization.',
          );
        }
        final shared = {...?_settings['twitch'], 'clientId': clientId};
        await dataService.savePluginSettings(
          'twitch',
          shared,
          expectedRevision: _storageRevisions['twitch'],
        );
        if (!mounted || !identical(owner, _loadOwner)) return;
        _storageRevisions['twitch'] = DocumentRevision.of(shared);
        await TwitchAccountAuthService(
          dataService: dataService,
        ).authorizeAccount('channel');
        final values = await loadTwitchChannelSettings(dataService);
        if (!mounted || !identical(owner, _loadOwner)) return;
        _settings['twitch'] = values;
        for (final entry in values.entries) {
          _controllers['twitch:${entry.key}']?.text = '${entry.value ?? ''}';
        }
        return;
      }
      final isYouTube = pluginId == 'youtube';
      if (clientId.isEmpty || (!isYouTube && clientSecret.isEmpty)) {
        throw ArgumentError(
          isYouTube
              ? 'Client ID is required before YouTube authorization.'
              : 'Client ID and client secret are required before authorization.',
        );
      }
      if (!isYouTube) {
        throw UnsupportedError('This provider has no authorization flow.');
      }
      final configured = {
        ...?_settings[pluginId],
        'clientId': clientId,
        'clientSecret': clientSecret,
      };
      await dataService.savePluginSettings(
        pluginId,
        configured,
        expectedRevision: _storageRevisions[pluginId],
      );
      if (!mounted || !identical(owner, _loadOwner)) return;
      _storageRevisions[pluginId] = DocumentRevision.of(configured);
      final connected = await YouTubeAuthService(
        dataService: dataService,
      ).connect();
      if (!mounted || !identical(owner, _loadOwner)) return;
      _settings[pluginId] = connected;
      _storageRevisions[pluginId] = DocumentRevision.of(connected);
      for (final entry in connected.entries) {
        _controllers['$pluginId:${entry.key}']?.text = encodePluginSettingValue(
          entry.value,
        );
      }
    } catch (error) {
      if (!mounted || !identical(owner, _loadOwner)) return;
      _error = error;
    } finally {
      if (mounted && identical(owner, _loadOwner)) {
        setState(() => _saving = null);
      }
    }
  }

  Future<void> _pairHueBridge() async {
    final owner = _loadOwner;
    final dataService = widget.dataService;
    setState(() {
      _huePairing = true;
      _huePaired = false;
      _error = null;
    });
    try {
      final pairing = await const PhilipsHueDiscoveryService().findAndPair();
      if (!mounted || !identical(owner, _loadOwner)) return;
      if (pairing == null) {
        throw StateError(
          'No Philips Hue bridge was paired. Press the bridge button and try again.',
        );
      }
      final values = <String, dynamic>{
        ..._settings['philips-hue'] ?? const <String, dynamic>{},
        'hubIp': pairing.host,
        'hubKey': pairing.applicationKey,
      };
      await dataService.savePluginSettings(
        'philips-hue',
        values,
        expectedRevision: _storageRevisions['philips-hue'],
      );
      if (!mounted || !identical(owner, _loadOwner)) return;
      _storageRevisions['philips-hue'] = DocumentRevision.of(values);
      _settings['philips-hue'] = values;
      _controllers['philips-hue:hubIp']?.text = pairing.host;
      _controllers['philips-hue:hubKey']?.text = pairing.applicationKey;
      _huePaired = true;
    } catch (error) {
      if (!mounted || !identical(owner, _loadOwner)) return;
      _error = error;
    }
    if (mounted && identical(owner, _loadOwner)) {
      setState(() => _huePairing = false);
    }
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
            child: const Text(
              'Plugin registry unavailable. Check plugin configuration and retry.',
            ),
          );
        }
        if (_loadFailed) {
          return Center(
            child: WorkspaceNotice(
              title: 'Plugin settings unavailable',
              message:
                  'Settings could not be loaded. Check storage access and retry.',
              action: TextButton(
                onPressed: () {
                  setState(() {
                    _loadOwner = Object();
                    _loading = true;
                  });
                  _load();
                },
                child: const Text('Retry'),
              ),
            ),
          );
        }
        final registry = snapshot.data;
        if (registry == null) {
          return const Center(child: Text('Plugin registry is unavailable'));
        }
        final plugins = snapshot.data?.plugins.toList() ?? const [];
        final selected = plugins
            .where((p) => p.id.value == _selectedPluginId)
            .firstOrNull;
        return ListenableBuilder(
          listenable: registry,
          builder: (context, child) {
            if (selected == null) {
              return const Center(child: Text('Select an integration'));
            }
            final contribution = registry.uiFor(selected.id.value);
            if (contribution != null && !widget.forceGenericDetails) {
              return contribution.build(
                context,
                DartPluginUiHostContext(
                  dataService: widget.dataService,
                  providerEvents: widget.providerEvents,
                  registryFuture: widget.registryFuture,
                  commands: widget.commands,
                  onOpenWorkspace: widget.onOpenWorkspace,
                ),
              );
            }
            return PluginDetailsView(
              key: ValueKey(selected.id.value),
              plugin: selected,
              registry: registry,
              dataService: widget.dataService,
              onEnabled: (value) => _setEnabled(selected.id.value, value),
              settingsBuilder: (context, filter) =>
                  _buildProviderSettings(context, selected.id.value, filter),
            );
          },
        );
      },
    );
  }

  Widget _buildProviderSettings(
    BuildContext context,
    String selectedPluginId,
    String filter,
  ) {
    final fields = _fields[selectedPluginId] ?? const <String>[];
    final visibleFields = fields.where((field) {
      final definition = _definitions['$selectedPluginId:$field'];
      return definition != null &&
          ('${definition.displayName} $field').toLowerCase().contains(
            filter.trim().toLowerCase(),
          );
    }).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Configure local transports and provider credentials for the Dart runtime.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        if (_error != null)
          const WorkspaceNotice(
            message:
                'Plugin settings could not be updated. Check the fields, permissions and storage access, then retry.',
          ),
        if (visibleFields.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              filter.trim().isEmpty
                  ? 'No plugin settings registered.'
                  : 'No matches for "${filter.trim()}".',
            ),
          )
        else
          Column(
            children: [
              if (selectedPluginId == 'philips-hue') ...[
                Card(
                  child: ListTile(
                    leading: Icon(
                      _huePaired ? Icons.check_circle : Icons.lightbulb_outline,
                      color: _huePaired ? Colors.green : null,
                    ),
                    title: const Text('Philips Hue Bridge'),
                    subtitle: Text(
                      _huePaired
                          ? 'Hub paired and credentials saved.'
                          : 'Press the button on the Hue bridge, then pair it automatically.',
                    ),
                    trailing: OutlinedButton(
                      onPressed: _huePairing ? null : _pairHueBridge,
                      child: Text(_huePairing ? 'Searching...' : 'Pair Hub'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
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
          value: decodePluginSettingBoolean(controller.text) ?? false,
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
    return PluginSettingTextField(
      definition: definition,
      controller: controller,
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
