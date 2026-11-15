import 'dart:async';

import 'package:flutter/material.dart';

import '../../../features/plugins/plugin_workspace.dart';
import '../../../services/showrunner_data_service.dart';
import '../../registry/plugin_registry.dart';
import '../../runtime/provider_event_workers.dart';
import '../auth_service.dart';

class KickWorkspace extends StatefulWidget {
  const KickWorkspace({
    super.key,
    required this.dataService,
    required this.providerEvents,
    required this.registryFuture,
  });
  final ShowRunnerDataService dataService;
  final ProviderEventRuntime providerEvents;
  final Future<DartPluginRegistry> registryFuture;
  @override
  State<KickWorkspace> createState() => _KickWorkspaceState();
}

class _KickWorkspaceState extends State<KickWorkspace> {
  Object _owner = Object();
  KickAuthService? _auth;
  bool _busy = false;
  String? _error;
  int _settingsEpoch = 0;

  @override
  void didUpdateWidget(covariant KickWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataService != widget.dataService ||
        oldWidget.providerEvents != widget.providerEvents ||
        oldWidget.registryFuture != widget.registryFuture) {
      _owner = Object();
      unawaited(_auth?.close());
      _auth = null;
      _busy = false;
      _error = null;
      _settingsEpoch++;
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    final owner = _owner;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted && identical(owner, _owner)) {
        _error =
            'Kick operation failed. Check saved credentials, webhook settings and permissions.';
      }
    }
    if (mounted && identical(owner, _owner)) {
      setState(() {
        _busy = false;
        _settingsEpoch++;
      });
    }
  }

  Future<void> _connect() async {
    final auth = KickAuthService(dataService: widget.dataService);
    _auth = auth;
    try {
      await auth.connect();
    } finally {
      await auth.close();
      if (identical(_auth, auth)) _auth = null;
    }
  }

  Future<void> _stopListener() async {
    final owner = _owner;
    final events = widget.providerEvents;
    try {
      await events.stopKickChat();
    } catch (_) {
      if (mounted && identical(owner, _owner)) {
        setState(() => _error = 'Kick listener could not stop cleanly. Retry.');
      }
    }
  }

  @override
  void dispose() {
    _owner = Object();
    unawaited(_auth?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Column(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: constraints.maxHeight * 0.6),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Kick connection',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  ListenableBuilder(
                    listenable: widget.providerEvents,
                    builder: (context, _) => Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Listener: ${widget.providerEvents.kickState.label}',
                        ),
                        FilledButton(
                          onPressed: _busy ? null : () => _run(_connect),
                          child: const Text('Connect Kick'),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  final events = widget.providerEvents;
                                  _run(events.startKickChat);
                                },
                          child: const Text('Start listener'),
                        ),
                        TextButton(
                          onPressed: _auth != null ? null : _stopListener,
                          child: const Text('Stop listener'),
                        ),
                        if (_auth != null)
                          TextButton(
                            onPressed: () => _auth?.close(),
                            child: const Text('Cancel sign-in'),
                          ),
                      ],
                    ),
                  ),
                  ExpansionTile(
                    title: const Text('Set up Kick Developer and webhook'),
                    children: [
                      const SizedBox(height: 8),
                      const Text(
                        'Save the client ID and secret below, then connect the broadcaster account. '
                        'Register this OAuth redirect URL in Kick Developer:',
                      ),
                      const SelectableText(kickOAuthRedirectUrl),
                      const SizedBox(height: 8),
                      const Text(
                        'Enable webhooks in Kick Developer and register your public HTTPS '
                        '/kick/webhook URL. Forward it only to this listener on local port 53544 '
                        '(or the saved Local Webhook Port). Messages appear in Chat.',
                      ),
                    ],
                  ),
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: PluginWorkspace(
            key: ValueKey((_owner, _settingsEpoch)),
            dataService: widget.dataService,
            registryFuture: widget.registryFuture,
            providerEvents: widget.providerEvents,
            selectedPluginId: 'kick',
            forceGenericDetails: true,
          ),
        ),
      ],
    ),
  );
}
