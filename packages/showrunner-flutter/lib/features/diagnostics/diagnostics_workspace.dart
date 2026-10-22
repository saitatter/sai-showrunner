import 'package:flutter/material.dart';

import '../../app/startup_health.dart';
import '../../design_system/workspace_notice.dart';
import '../../plugins/runtime/provider_event_workers.dart';
import '../../plugins/registry/plugin_registry.dart';
import '../../runtime/action_queue.dart';

class DiagnosticsWorkspace extends StatelessWidget {
  const DiagnosticsWorkspace({
    super.key,
    required this.healthFuture,
    required this.queue,
    required this.providerEvents,
    required this.registryFuture,
  });

  final Future<StartupHealthSnapshot> healthFuture;
  final DartActionQueue queue;
  final ProviderEventRuntime providerEvents;
  final Future<DartPluginRegistry> registryFuture;

  @override
  Widget build(BuildContext context) => FutureBuilder<StartupHealthSnapshot>(
    future: healthFuture,
    builder: (context, snapshot) {
      final result = snapshot.data;
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Diagnostics', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          ListTile(
            leading: Icon(
              result?.state == StartupHealthState.ready
                  ? Icons.check_circle
                  : Icons.warning,
            ),
            title: Text(result?.state.name ?? 'loading'),
            subtitle: Text(
              result?.health?.settingsFileCount.toString() ??
                  'Checking local data',
            ),
          ),
          if (result?.error != null)
            const WorkspaceNotice(
              message:
                  'Startup checks failed. Check local storage and configuration.',
            ),
          const SizedBox(height: 20),
          _QueueDiagnostics(queue: queue),
          const SizedBox(height: 16),
          _ProviderDiagnostics(providerEvents: providerEvents),
          const SizedBox(height: 16),
          _PluginHealthDiagnostics(registryFuture: registryFuture),
        ],
      );
    },
  );
}

class _ProviderDiagnostics extends StatelessWidget {
  const _ProviderDiagnostics({required this.providerEvents});

  final ProviderEventRuntime providerEvents;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: providerEvents,
    builder: (context, child) => Card(
      child: Column(
        children: [
          const ListTile(
            leading: Icon(Icons.sensors),
            title: Text('Provider event workers'),
          ),
          ListTile(
            dense: true,
            leading: _providerStateIcon(providerEvents.twitchState),
            title: const Text('Twitch EventSub'),
            subtitle: Text(
              _providerStateText(
                providerEvents.twitchState,
                error: providerEvents.twitchLastError,
                attempts: providerEvents.twitchReconnectAttempts,
              ),
            ),
          ),
          if (providerEvents.twitchSubscriptionErrors.isNotEmpty)
            ListTile(
              dense: true,
              leading: const Icon(Icons.warning_amber, color: Colors.orange),
              title: const Text('Twitch subscriptions'),
              subtitle: Text(
                '${providerEvents.twitchSubscriptionErrors.length} subscription(s) failed. Check permissions and reconnect Twitch.',
              ),
            ),
          ListTile(
            dense: true,
            leading: _providerStateIcon(providerEvents.youtubeState),
            title: const Text('YouTube Live Chat'),
            subtitle: Text(
              _providerStateText(
                providerEvents.youtubeState,
                error: providerEvents.youtubeLastError,
                attempts: providerEvents.youtubeFailureCount,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

Icon _providerStateIcon(ProviderWorkerState state) {
  final (icon, color) = switch (state) {
    ProviderWorkerState.stopped => (Icons.radio_button_unchecked, null),
    ProviderWorkerState.starting => (Icons.hourglass_top, Colors.orange),
    ProviderWorkerState.running => (Icons.check_circle, Colors.green),
    ProviderWorkerState.reconnecting => (Icons.sync_problem, Colors.orange),
    ProviderWorkerState.error => (Icons.error_outline, Colors.redAccent),
  };
  return Icon(icon, color: color);
}

String _providerStateText(
  ProviderWorkerState state, {
  Object? error,
  int attempts = 0,
}) {
  final details = <String>[state.label];
  if (attempts > 0) details.add('attempts $attempts');
  if (error != null) {
    details.add(
      'Last operation failed. Check authentication and connectivity.',
    );
  }
  return details.join(' | ');
}

class _QueueDiagnostics extends StatelessWidget {
  const _QueueDiagnostics({required this.queue});

  final DartActionQueue queue;

  @override
  Widget build(BuildContext context) => StreamBuilder<QueuedGraphExecution?>(
    stream: queue.changes,
    initialData: queue.running,
    builder: (context, snapshot) => Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Action queue',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                IconButton(
                  tooltip: queue.paused ? 'Resume queue' : 'Pause queue',
                  onPressed: () => queue.setPaused(!queue.paused),
                  icon: Icon(queue.paused ? Icons.play_arrow : Icons.pause),
                ),
                IconButton(
                  tooltip: 'Clear pending actions',
                  onPressed: queue.pending.isEmpty ? null : queue.clearPending,
                  icon: const Icon(Icons.clear_all),
                ),
              ],
            ),
            Text(
              queue.paused
                  ? 'Paused'
                  : queue.running == null
                  ? 'Ready'
                  : queue.running!.status,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                _QueueCount(label: 'Pending', value: queue.pending.length),
                _QueueCount(
                  label: 'Running',
                  value: queue.running == null ? 0 : 1,
                ),
                _QueueCount(label: 'History', value: queue.history.length),
              ],
            ),
            if (queue.running != null) ...[
              const Divider(height: 24),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  queue.running!.status == 'cancelling'
                      ? Icons.hourglass_top
                      : Icons.bolt,
                ),
                title: Text(
                  'Running: ${queue.running!.source['name'] ?? queue.running!.id}',
                ),
                subtitle: Text(
                  [
                    queue.running!.id,
                    queue.running!.status,
                    if (queue.running!.startedAt != null)
                      'started ${queue.running!.startedAt!.toLocal()}',
                    if (queue.running!.reason != null) queue.running!.reason!,
                  ].join(' | '),
                ),
                trailing: IconButton(
                  tooltip: queue.running!.status == 'cancelling'
                      ? 'Cancelling'
                      : 'Cancel running action',
                  onPressed: queue.running!.status == 'cancelling'
                      ? null
                      : queue.cancelRunning,
                  icon: const Icon(Icons.stop_circle_outlined),
                ),
              ),
            ],
            if (queue.history.isNotEmpty) ...[
              const Divider(height: 24),
              Text('Latest result: ${queue.history.first.status}'),
              if (queue.history.first.reason != null)
                Text(queue.history.first.reason!),
              if (queue.history.first.error != null)
                Text(
                  queue.history.first.errorUserMessage ??
                      'The queued action failed. Inspect its execution trace for details.',
                ),
              if (queue.history.first.errorCode != null)
                Text(
                  [
                    queue.history.first.errorCode!,
                    if (queue.history.first.errorPluginId != null)
                      queue.history.first.errorPluginId!,
                    if (queue.history.first.errorOperationId != null)
                      queue.history.first.errorOperationId!,
                    if (queue.history.first.errorRetryable == true) 'retryable',
                  ].join(' | '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ],
        ),
      ),
    ),
  );
}

typedef _HealthRow = ({DartPluginManifest plugin, DartPluginHealth? health});

class _PluginHealthDiagnostics extends StatefulWidget {
  const _PluginHealthDiagnostics({required this.registryFuture});
  final Future<DartPluginRegistry> registryFuture;
  @override
  State<_PluginHealthDiagnostics> createState() =>
      _PluginHealthDiagnosticsState();
}

class _PluginHealthDiagnosticsState extends State<_PluginHealthDiagnostics> {
  late Future<List<_HealthRow>> _future;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant _PluginHealthDiagnostics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.registryFuture != widget.registryFuture) _reload();
  }

  void _reload() {
    _future = _load(widget.registryFuture);
  }

  Future<List<_HealthRow>> _load(Future<DartPluginRegistry> future) async {
    final registry = await future;
    return List.unmodifiable(
      await Future.wait([
        for (final plugin in registry.plugins)
          () async {
            DartPluginHealth? health;
            try {
              health = await registry.checkHealthDetailsId(plugin.id);
            } on Object {
              /* Safe unavailable state below. */
            }
            return (plugin: plugin, health: health);
          }(),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<_HealthRow>>(
    future: _future,
    builder: (context, snapshot) => Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.extension_outlined),
            title: const Text('Plugin health'),
            trailing: IconButton(
              tooltip: 'Refresh plugin health',
              onPressed: snapshot.connectionState == ConnectionState.waiting
                  ? null
                  : () => setState(_reload),
              icon: const Icon(Icons.refresh),
            ),
          ),
          if (snapshot.hasError)
            const WorkspaceNotice(
              message:
                  'Plugin health is unavailable. Retry after checking the configuration.',
            )
          else if (snapshot.connectionState == ConnectionState.waiting)
            const ListTile(title: Text('Loading plugin registry'))
          else if (snapshot.data!.isEmpty)
            const ListTile(title: Text('No registered plugins'))
          else
            for (final row in snapshot.data!)
              ListTile(
                dense: true,
                leading: Icon(
                  row.health?.isHealthy == true
                      ? Icons.check_circle
                      : Icons.warning,
                  color: row.health?.isHealthy == true
                      ? Colors.teal
                      : Colors.orange,
                ),
                title: Text(row.plugin.name),
                subtitle: Text(
                  row.health == null
                      ? 'Health check failed. Check the provider connection.'
                      : row.health!.isHealthy
                      ? 'Ready'
                      : row.health!.status.name,
                ),
              ),
        ],
      ),
    ),
  );
}

class _QueueCount extends StatelessWidget {
  const _QueueCount({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$value', style: Theme.of(context).textTheme.headlineMedium),
      Text(label),
    ],
  );
}
