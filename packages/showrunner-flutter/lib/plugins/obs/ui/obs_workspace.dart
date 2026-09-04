import 'package:flutter/material.dart';

import '../../registry/plugin_registry.dart';
import '../../../services/provider_settings_validator.dart';
import '../../../services/showrunner_data_service.dart';

class ObsWorkspace extends StatefulWidget {
  const ObsWorkspace({
    super.key,
    required this.dataService,
    required this.registryFuture,
  });

  final ShowRunnerDataService dataService;
  final Future<DartPluginRegistry> registryFuture;

  @override
  State<ObsWorkspace> createState() => _ObsWorkspaceState();
}

class _ObsWorkspaceState extends State<ObsWorkspace> {
  bool _busy = false;
  bool? _healthy;
  Object? _error;
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
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await widget.dataService.loadPluginSettings('obs');
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

  Future<void> _invoke(String actionId, Map<String, dynamic> config) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final registry = await widget.registryFuture;
      await registry.invokeAction('obs', actionId, config);
      _healthy = true;
    } catch (error) {
      _error = error;
      _healthy = false;
    }
    if (mounted) setState(() => _busy = false);
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
