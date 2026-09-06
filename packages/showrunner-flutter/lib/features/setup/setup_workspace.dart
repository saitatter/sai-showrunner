import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/showrunner_data_service.dart';
import 'obs_setup_persistence.dart';

class SetupWorkspace extends StatefulWidget {
  const SetupWorkspace({
    super.key,
    required this.dataService,
    required this.onOpenPlugin,
  });

  final ShowRunnerDataService dataService;
  final ValueChanged<String> onOpenPlugin;

  @override
  State<SetupWorkspace> createState() => _SetupWorkspaceState();
}

class _SetupWorkspaceState extends State<SetupWorkspace> {
  static const _steps = <String>['twitch', 'youtube', 'obs', 'done'];

  final _clientIdController = TextEditingController();
  final _clientSecretController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _passwordController = TextEditingController();
  final _settings = <String, Map<String, dynamic>>{};
  final _obsPersistence = const ObsSetupPersistence();
  String? _obsResourceId;
  int _stepIndex = 0;
  bool _loading = true;
  bool _saving = false;
  bool _testingObs = false;
  bool? _obsTestPassed;
  Object? _obsTestError;
  Object? _error;

  String get _pluginId => _steps[_stepIndex];
  bool get _isDone => _pluginId == 'done';

  @override
  void initState() {
    super.initState();
    _loadStep();
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _clientSecretController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadStep() async {
    if (_isDone) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settings = await widget.dataService.loadPluginSettings(_pluginId);
      _settings[_pluginId] = settings;
      if (_pluginId == 'obs') {
        _obsTestPassed = null;
        _obsTestError = null;
        await _loadObsResource(settings);
      } else {
        _fillControllers(settings);
      }
    } catch (error) {
      _error = error;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadObsResource(Map<String, dynamic> settings) async {
    final directory = Directory(
      '${widget.dataService.userDirectory.path}/obs/connections',
    );
    final selected = await _obsPersistence.loadSelected(
      directory: directory,
      settings: settings,
    );
    _obsResourceId = selected?.id;
    _fillControllers({...settings, ...?selected?.config});
  }

  void _fillControllers(Map<String, dynamic> settings) {
    _clientIdController.text = settings['clientId']?.toString() ?? '';
    _clientSecretController.text = settings['clientSecret']?.toString() ?? '';
    _hostController.text = settings['host']?.toString() ?? '127.0.0.1';
    _portController.text = settings['port']?.toString() ?? '4455';
    _passwordController.text = settings['password']?.toString() ?? '';
  }

  bool get _ready {
    if (_pluginId == 'obs') {
      final port = int.tryParse(_portController.text.trim());
      return _hostController.text.trim().isNotEmpty &&
          port != null &&
          port > 0 &&
          port <= 65535;
    }
    final settings = _settings[_pluginId] ?? const <String, dynamic>{};
    return (_clientIdController.text.trim().isNotEmpty &&
            _clientSecretController.text.trim().isNotEmpty) ||
        settings['accessToken']?.toString().isNotEmpty == true ||
        settings['refreshToken']?.toString().isNotEmpty == true;
  }

  Future<void> _saveStep() async {
    if (_isDone) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final current = <String, dynamic>{...?_settings[_pluginId]};
      if (_pluginId == 'obs') {
        final host = _hostController.text.trim();
        final port = int.tryParse(_portController.text.trim()) ?? 4455;
        final id = await _obsPersistence.save(
          directory: Directory(
            '${widget.dataService.userDirectory.path}/obs/connections',
          ),
          resourceId: _obsResourceId,
          host: host,
          port: port,
          password: _passwordController.text,
        );
        _obsResourceId = id;
        current['obsDefault'] = id;
      } else {
        current['clientId'] = _clientIdController.text.trim();
        current['clientSecret'] = _clientSecretController.text;
      }
      await widget.dataService.savePluginSettings(_pluginId, current);
      _settings[_pluginId] = current;
      _stepIndex++;
      if (_isDone) await _markComplete();
      if (_stepIndex < _steps.length) await _loadStep();
    } catch (error) {
      _error = error;
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _testObsConnection() async {
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim());
    if (host.isEmpty || port == null || port < 1 || port > 65535) {
      setState(() {
        _obsTestPassed = false;
        _obsTestError = StateError('Enter a valid OBS host and port first.');
      });
      return;
    }
    setState(() {
      _testingObs = true;
      _obsTestPassed = null;
      _obsTestError = null;
    });
    try {
      await const ObsSetupConnectionTester().verify(
        host: host,
        port: port,
        password: _passwordController.text,
      );
      if (mounted) setState(() => _obsTestPassed = true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _obsTestPassed = false;
          _obsTestError = error;
        });
      }
    } finally {
      if (mounted) setState(() => _testingObs = false);
    }
  }

  Future<void> _skip() async {
    if (_stepIndex >= _steps.length - 1) return;
    setState(() => _stepIndex++);
    if (_isDone) {
      await _markComplete();
    } else {
      await _loadStep();
    }
  }

  Future<void> _markComplete() async {
    final settings = await widget.dataService.loadPluginSettings(
      'showrunner-flutter',
    );
    await widget.dataService.savePluginSettings('showrunner-flutter', {
      ...settings,
      'setupCompleted': true,
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'First-run setup',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          _isDone
              ? 'Setup complete. Provider credentials can be authorized from Plugins.'
              : 'Configure the providers ShowRunner uses for chat, automation, and OBS control.',
        ),
        const SizedBox(height: 24),
        _StepIndicator(current: _stepIndex),
        const SizedBox(height: 24),
        if (_isDone)
          _DoneStep(onOpenPlugins: () => widget.onOpenPlugin('twitch'))
        else
          _buildProviderStep(context),
      ],
    );
  }

  Widget _buildProviderStep(BuildContext context) {
    final providerName = _pluginId == 'obs'
        ? 'OBS Studio'
        : _pluginId == 'twitch'
        ? 'Twitch'
        : 'YouTube';
    final description = _pluginId == 'obs'
        ? 'ShowRunner connects through the OBS WebSocket server.'
        : 'Save OAuth client credentials, then finish authorization in Plugins.';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(_pluginId == 'obs' ? Icons.tv : Icons.live_tv),
                const SizedBox(width: 10),
                Text(
                  providerName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(description),
            const SizedBox(height: 20),
            if (_pluginId == 'obs') ...[
              TextField(
                controller: _hostController,
                decoration: const InputDecoration(
                  labelText: 'Server host',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _portController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Server port',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Server password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _testingObs ? null : _testObsConnection,
                    icon: _testingObs
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    label: const Text('Test connection'),
                  ),
                  const SizedBox(width: 12),
                  if (_obsTestPassed == true)
                    const Text(
                      'Connected and responding.',
                      style: TextStyle(color: Colors.green),
                    ),
                  if (_obsTestPassed == false)
                    Expanded(
                      child: Text(
                        'Connection failed: $_obsTestError',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ] else ...[
              TextField(
                controller: _clientIdController,
                decoration: const InputDecoration(
                  labelText: 'OAuth client ID',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _clientSecretController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'OAuth client secret',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  _ready ? Icons.check_circle : Icons.info_outline,
                  color: _ready ? Colors.green : null,
                ),
                title: Text(
                  _ready
                      ? 'Credentials are present'
                      : 'Authorization is still required',
                ),
                subtitle: const Text(
                  'Use the Plugins tab to run the browser authorization flow.',
                ),
                trailing: OutlinedButton(
                  onPressed: () => widget.onOpenPlugin(_pluginId),
                  child: const Text('Open Plugins'),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                'Setup error: $_error',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                if (_stepIndex > 0)
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () {
                            setState(() => _stepIndex--);
                            _loadStep();
                          },
                    child: const Text('Back'),
                  ),
                const Spacer(),
                OutlinedButton(
                  onPressed: _saving ? null : _skip,
                  child: const Text('Skip'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _saving || !_ready ? null : _saveStep,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_forward),
                  label: Text(
                    _stepIndex == _steps.length - 2
                        ? 'Finish'
                        : 'Save and continue',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var index = 0; index < 4; index++) ...[
        CircleAvatar(
          radius: 15,
          backgroundColor: index <= current
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Text('${index + 1}'),
        ),
        if (index < 3)
          Expanded(
            child: Divider(
              color: index < current
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
          ),
      ],
    ],
  );
}

class _DoneStep extends StatelessWidget {
  const _DoneStep({required this.onOpenPlugins});

  final VoidCallback onOpenPlugins;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 48),
          const SizedBox(height: 12),
          Text('Setup complete', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            'Provider settings are saved. Open Plugins to authorize Twitch or YouTube and verify each connection.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onOpenPlugins,
            icon: const Icon(Icons.extension_outlined),
            label: const Text('Open Plugins'),
          ),
        ],
      ),
    ),
  );
}
