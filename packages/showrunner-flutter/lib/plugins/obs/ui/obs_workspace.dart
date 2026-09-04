import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../registry/plugin_registry.dart';
import '../../../services/provider_settings_validator.dart';
import '../../../services/showrunner_data_service.dart';
import '../../../runtime/expression.dart';
import '../catalog_runtime.dart';

class ObsWorkspace extends StatefulWidget {
  const ObsWorkspace({
    super.key,
    required this.dataService,
    required this.registryFuture,
    this.catalogService,
    this.settingsFuture,
  });

  final ShowRunnerDataService dataService;
  final Future<DartPluginRegistry> registryFuture;
  final ObsCatalogService? catalogService;
  final Future<Map<String, dynamic>>? settingsFuture;

  @override
  State<ObsWorkspace> createState() => _ObsWorkspaceState();
}

class _ObsTransformDialog extends StatefulWidget {
  const _ObsTransformDialog({
    required this.sourceName,
    required this.positionX,
    required this.positionY,
    required this.scaleX,
    required this.scaleY,
    required this.rotation,
  });

  final String sourceName;
  final double positionX;
  final double positionY;
  final double scaleX;
  final double scaleY;
  final double rotation;

  @override
  State<_ObsTransformDialog> createState() => _ObsTransformDialogState();
}

class _ObsTransformDialogState extends State<_ObsTransformDialog> {
  late final TextEditingController _positionX;
  late final TextEditingController _positionY;
  late final TextEditingController _scaleX;
  late final TextEditingController _scaleY;
  late final TextEditingController _rotation;

  @override
  void initState() {
    super.initState();
    _positionX = TextEditingController(text: '${widget.positionX}');
    _positionY = TextEditingController(text: '${widget.positionY}');
    _scaleX = TextEditingController(text: '${widget.scaleX}');
    _scaleY = TextEditingController(text: '${widget.scaleY}');
    _rotation = TextEditingController(text: '${widget.rotation}');
  }

  @override
  void dispose() {
    _positionX.dispose();
    _positionY.dispose();
    _scaleX.dispose();
    _scaleY.dispose();
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Transform ${widget.sourceName}'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _numberField(_positionX, 'Position X'),
          _numberField(_positionY, 'Position Y'),
          _numberField(_scaleX, 'Scale X'),
          _numberField(_scaleY, 'Scale Y'),
          _numberField(_rotation, 'Rotation'),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Apply')),
    ],
  );

  Widget _numberField(TextEditingController controller, String label) =>
      TextField(
        controller: controller,
        decoration: InputDecoration(labelText: label),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
      );

  void _save() {
    final values = [
      double.tryParse(_positionX.text),
      double.tryParse(_positionY.text),
      double.tryParse(_scaleX.text),
      double.tryParse(_scaleY.text),
      double.tryParse(_rotation.text),
    ];
    if (values.any((value) => value == null)) return;
    Navigator.pop(context, {
      'position': {'x': values[0], 'y': values[1]},
      'scale': {'x': values[2], 'y': values[3]},
      'rotation': values[4],
    });
  }
}

class _ObsInputSettingsDialog extends StatefulWidget {
  const _ObsInputSettingsDialog({
    required this.sourceName,
    required this.settings,
  });

  final String sourceName;
  final RuntimeMap settings;

  @override
  State<_ObsInputSettingsDialog> createState() =>
      _ObsInputSettingsDialogState();
}

class _ObsInputSettingsDialogState extends State<_ObsInputSettingsDialog> {
  late final TextEditingController _settings;
  String? _error;

  @override
  void initState() {
    super.initState();
    _settings = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(widget.settings),
    );
  }

  @override
  void dispose() {
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Edit ${widget.sourceName} settings'),
    content: SizedBox(
      width: 600,
      child: TextField(
        controller: _settings,
        minLines: 10,
        maxLines: 20,
        decoration: InputDecoration(
          labelText: 'Input settings (JSON object)',
          errorText: _error,
          border: const OutlineInputBorder(),
        ),
        keyboardType: TextInputType.multiline,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Apply')),
    ],
  );

  void _save() {
    try {
      final decoded = jsonDecode(_settings.text);
      if (decoded is! Map) {
        throw const FormatException('Settings must be a JSON object.');
      }
      Navigator.pop(context, Map<String, dynamic>.from(decoded));
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    } on Object {
      setState(() => _error = 'Settings must be valid JSON.');
    }
  }
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

double _number(Object? value, [double fallback = 0]) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;

class _ObsWorkspaceState extends State<ObsWorkspace> {
  bool _busy = false;
  bool? _healthy;
  Object? _error;
  ObsSceneCatalog? _catalog;
  Object? _catalogError;
  bool _catalogLoading = false;
  String? _selectedScene;
  bool _settingsLoading = true;
  bool _settingsSaving = false;
  Object? _settingsError;
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _passwordController = TextEditingController();
  final _sceneController = TextEditingController();
  final _browserSourceController = TextEditingController();
  final _browserUrlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
    unawaited(_refreshCatalog());
  }

  Future<void> _loadSettings() async {
    try {
      final settings =
          await (widget.settingsFuture ??
              widget.dataService.loadPluginSettings('obs'));
      _hostController.text = settings['host']?.toString() ?? '127.0.0.1';
      _portController.text = settings['port']?.toString() ?? '4455';
      _passwordController.text = settings['password']?.toString() ?? '';
    } catch (error) {
      _settingsError = error;
    }
    if (mounted) setState(() => _settingsLoading = false);
  }

  Future<void> _saveSettings() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim());
    final password = _passwordController.text;
    final settings = <String, dynamic>{
      'host': host,
      'port': port,
      if (password.isNotEmpty) 'password': password,
    };
    final validation = validateProviderSettings('obs', settings);
    if (!validation.isValid) {
      setState(
        () => _settingsError = ArgumentError(validation.errors.join(' ')),
      );
      return;
    }
    setState(() {
      _settingsSaving = true;
      _settingsError = null;
    });
    try {
      await widget.dataService.savePluginSettings('obs', settings);
    } catch (error) {
      _settingsError = error;
    }
    if (mounted) setState(() => _settingsSaving = false);
  }

  Future<void> _checkConnection() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _healthy = await widget.registryFuture.then((registry) {
        return registry.checkHealth('obs');
      });
    } catch (error) {
      _healthy = false;
      _error = error;
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _refreshCatalog() async {
    setState(() {
      _catalogLoading = true;
      _catalogError = null;
    });
    try {
      final catalog =
          await (widget.catalogService ??
                  ObsCatalogService(dataService: widget.dataService))
              .load();
      if (mounted) {
        setState(() {
          _catalog = catalog;
          _selectedScene = catalog.scenes.contains(_selectedScene)
              ? _selectedScene
              : catalog.currentProgramScene ?? catalog.scenes.firstOrNull;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _catalogError = error);
    } finally {
      if (mounted) setState(() => _catalogLoading = false);
    }
  }

  Future<void> _setSceneItemEnabled(ObsSceneItem item, bool enabled) async {
    final scene = _selectedScene;
    if (scene == null) return;
    await _invoke('source', {
      'scene': scene,
      'source': item.id,
      'enabled': enabled,
    });
    await _refreshCatalog();
  }

  Future<void> _editTransform(ObsSceneItem item) async {
    final transform = item.transform;
    final position = _map(transform['position']);
    final scale = _map(transform['scale']);
    final values = await showDialog<RuntimeMap>(
      context: context,
      builder: (context) => _ObsTransformDialog(
        sourceName: item.sourceName,
        positionX: _number(transform['positionX'] ?? position['x']),
        positionY: _number(transform['positionY'] ?? position['y']),
        scaleX: _number(transform['scaleX'] ?? scale['x'], 1),
        scaleY: _number(transform['scaleY'] ?? scale['y'], 1),
        rotation: _number(transform['rotation']),
      ),
    );
    final scene = _selectedScene;
    if (values == null || scene == null) return;
    await _invoke('transform', {
      'scene': scene,
      'source': item.id,
      'transform': values,
    });
    await _refreshCatalog();
  }

  Future<Object?> _editInputSettings(ObsSceneItem item) async {
    final response = await _invoke('getInputSettings', {
      'sourceName': item.sourceName,
    });
    if (!mounted || response is! Map) return null;
    final settings = _map(response['inputSettings']);
    final updated = await showDialog<RuntimeMap>(
      context: context,
      builder: (context) => _ObsInputSettingsDialog(
        sourceName: item.sourceName,
        settings: settings,
      ),
    );
    if (updated == null) return null;
    await _invoke('setInputSettings', {
      'sourceName': item.sourceName,
      'inputSettings': updated,
    });
    await _refreshCatalog();
    return updated;
  }

  Future<void> _setFilterEnabled(
    ObsSceneItem item,
    ObsSourceFilter filter,
    bool enabled,
  ) async {
    await _invoke('filter', {
      'sourceName': item.sourceName,
      'filterName': filter.name,
      'filterEnabled': enabled,
    });
    await _refreshCatalog();
  }

  Future<Object?> _invoke(String actionId, Map<String, dynamic> config) async {
    Object? result;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final registry = await widget.registryFuture;
      result = await registry.invokeAction('obs', actionId, config);
      _healthy = true;
    } catch (error) {
      _error = error;
      _healthy = false;
    }
    if (mounted) setState(() => _busy = false);
    return result;
  }

  Widget _buildSceneCatalog(BuildContext context) {
    final catalog = _catalog;
    final scene = _selectedScene;
    final items = scene == null
        ? const <ObsSceneItem>[]
        : catalog?.itemsByScene[scene] ?? const <ObsSceneItem>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Scenes and sources',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Refresh scenes and sources',
              onPressed: _catalogLoading ? null : _refreshCatalog,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (_catalogLoading)
          const LinearProgressIndicator()
        else if (catalog == null)
          Text('Unavailable: ${_catalogError ?? 'load the OBS catalog'}')
        else if (catalog.scenes.isEmpty)
          const Text('OBS returned no scenes.')
        else ...[
          DropdownButtonFormField<String>(
            initialValue: scene,
            decoration: const InputDecoration(labelText: 'Scene'),
            items: [
              for (final value in catalog.scenes)
                DropdownMenuItem(value: value, child: Text(value)),
            ],
            onChanged: (value) => setState(() => _selectedScene = value),
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            const Text('No sources in this scene.')
          else
            for (final item in items)
              Builder(
                builder: (context) {
                  final filters =
                      catalog.filtersBySource[item.sourceName] ??
                      const <ObsSourceFilter>[];
                  final inputKind = catalog.inputKindsByName[item.sourceName];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.sourceName),
                        subtitle: Text(
                          'Scene item ${item.id}'
                          '${inputKind?.isNotEmpty == true ? ' · $inputKind' : ''}',
                        ),
                        leading: Switch(
                          value: item.enabled,
                          onChanged: _busy
                              ? null
                              : (enabled) =>
                                    _setSceneItemEnabled(item, enabled),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (inputKind != null)
                              IconButton(
                                tooltip: 'Edit input settings',
                                onPressed: _busy
                                    ? null
                                    : () => _editInputSettings(item),
                                icon: const Icon(Icons.tune),
                              ),
                            IconButton(
                              tooltip: 'Edit transform',
                              onPressed: _busy
                                  ? null
                                  : () => _editTransform(item),
                              icon: const Icon(Icons.open_with),
                            ),
                          ],
                        ),
                      ),
                      if (filters.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 56),
                          child: Column(
                            children: [
                              for (final filter in filters)
                                SwitchListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  title: Text('Filter: ${filter.name}'),
                                  value: filter.enabled,
                                  onChanged: _busy
                                      ? null
                                      : (enabled) => _setFilterEnabled(
                                          item,
                                          filter,
                                          enabled,
                                        ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _passwordController.dispose();
    _sceneController.dispose();
    _browserSourceController.dispose();
    _browserUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text('OBS Studio', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text(
        'Connection used by actions, overlays, and stream automation.',
      ),
      const SizedBox(height: 24),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Connection settings',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _settingsLoading || _settingsSaving
                        ? null
                        : _saveSettings,
                    icon: _settingsSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: const Text('Save connection'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_settingsLoading)
                const Text('Loading connection settings...')
              else ...[
                TextField(
                  controller: _hostController,
                  decoration: const InputDecoration(labelText: 'Host'),
                  enabled: !_settingsSaving,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _portController,
                  decoration: const InputDecoration(labelText: 'Port'),
                  keyboardType: TextInputType.number,
                  enabled: !_settingsSaving,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                  enabled: !_settingsSaving,
                ),
              ],
              if (_settingsError != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Settings error: $_settingsError',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: ListTile(
          leading: Icon(
            _healthy == true ? Icons.check_circle : Icons.tv,
            color: _healthy == true ? Colors.green : null,
          ),
          title: const Text('OBS WebSocket'),
          subtitle: Text(
            _healthy == null
                ? 'Connection has not been checked.'
                : _healthy!
                ? 'Connected and responding.'
                : 'Not connected or not configured.',
          ),
          trailing: FilledButton.icon(
            onPressed: _busy ? null : _checkConnection,
            icon: const Icon(Icons.sync),
            label: const Text('Check'),
          ),
        ),
      ),
      if (_error != null)
        Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: ListTile(
            leading: const Icon(Icons.error_outline),
            title: const Text('OBS connection error'),
            subtitle: Text('$_error'),
          ),
        ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Quick controls',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sceneController,
                decoration: const InputDecoration(labelText: 'Scene name'),
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy || _sceneController.text.trim().isEmpty
                        ? null
                        : () => _invoke('scene', {
                            'scene': _sceneController.text.trim(),
                          }),
                    icon: const Icon(Icons.layers),
                    label: const Text('Set scene'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _invoke('streamStartStop', {
                            'streaming': 'toggle',
                          }),
                    icon: const Icon(Icons.broadcast_on_home),
                    label: const Text('Toggle stream'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _invoke('recordingStartStop', {
                            'recording': 'toggle',
                          }),
                    icon: const Icon(Icons.fiber_manual_record),
                    label: const Text('Toggle recording'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _buildSceneCatalog(context),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Browser source',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _browserSourceController,
                decoration: const InputDecoration(labelText: 'Source name'),
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _browserUrlController,
                decoration: const InputDecoration(labelText: 'Overlay URL'),
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed:
                        _busy ||
                            _browserSourceController.text.trim().isEmpty ||
                            _browserUrlController.text.trim().isEmpty
                        ? null
                        : () => _invoke('browserUrl', {
                            'source': _browserSourceController.text.trim(),
                            'url': _browserUrlController.text.trim(),
                          }),
                    icon: const Icon(Icons.link),
                    label: const Text('Set URL'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        _busy || _browserSourceController.text.trim().isEmpty
                        ? null
                        : () => _invoke('browserRefresh', {
                            'source': _browserSourceController.text.trim(),
                          }),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ],
  );
}
