import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../persistence/queue_config_repository.dart';
import '../../persistence/resource_repository.dart';
import '../../plugins/registry/plugin_registry.dart';
import '../../plugins/runtime/provider_event_workers.dart';
import '../../plugins/stream_plans/manifest.dart';
import '../../plugins/twitch/channel_runtime.dart';
import '../../runtime/action_queue.dart';
import '../../schema/queue.dart';
import '../../schema/resource.dart';
import '../../schema/stream_plan.dart';
import '../../services/showrunner_data_service.dart';

/// The desktop landing page from the reference application.
///
/// It intentionally reads the same persisted resources used by the catalog
/// workspaces. This keeps the page a live operational view instead of a
/// second, dashboard-specific copy of project state.
class MainDashboardWorkspace extends StatefulWidget {
  const MainDashboardWorkspace({
    super.key,
    required this.dataService,
    required this.actionQueue,
    required this.providerEvents,
    required this.registryFuture,
    this.streamPlanRuntime,
    required this.onOpenWorkspace,
    this.resourcesLoader,
  });

  final ShowRunnerDataService dataService;
  final DartActionQueue actionQueue;
  final ProviderEventRuntime providerEvents;
  final Future<DartPluginRegistry> registryFuture;
  final DartStreamPlanRuntime? streamPlanRuntime;
  final ValueChanged<int> onOpenWorkspace;
  final Future<MainDashboardData> Function()? resourcesLoader;

  @override
  State<MainDashboardWorkspace> createState() => _MainDashboardWorkspaceState();
}

final class MainDashboardData {
  const MainDashboardData({
    required this.obsConnections,
    required this.queues,
    required this.streamPlans,
    required this.twitchSettings,
  });

  final List<ResourceData> obsConnections;
  final List<({String fileName, QueueConfig? config, Object? error})> queues;
  final List<ResourceData> streamPlans;
  final Map<String, dynamic> twitchSettings;
}

class _MainDashboardWorkspaceState extends State<MainDashboardWorkspace> {
  late Future<MainDashboardData> _resourcesFuture;
  TwitchChannelSnapshot? _channelSnapshot;
  Object? _channelError;
  bool _channelLoading = false;

  @override
  void initState() {
    super.initState();
    _reloadResources();
  }

  void _reloadResources() {
    _resourcesFuture = widget.resourcesLoader?.call() ?? _loadResources();
  }

  Future<MainDashboardData> _loadResources() async {
    final root = widget.dataService.userDirectory.path;
    final results = await Future.wait<Object>([
      ResourceRepository(Directory('$root/obs/connections')).list(),
      QueueConfigRepository(Directory('$root/queues')).list(),
      ResourceRepository(Directory('$root/stream-plans')).list(),
      widget.dataService.loadPluginSettings('twitch'),
    ]);
    return MainDashboardData(
      obsConnections: (results[0] as List<ResourceData>),
      queues:
          (results[1]
              as List<({String fileName, QueueConfig? config, Object? error})>),
      streamPlans: results[2] as List<ResourceData>,
      twitchSettings: results[3] as Map<String, dynamic>,
    );
  }

  Future<void> _refreshChannel() async {
    if (_channelLoading) return;
    setState(() {
      _channelLoading = true;
      _channelError = null;
    });
    try {
      final snapshot = await TwitchChannelInfoService(
        dataService: widget.dataService,
      ).load();
      if (mounted) setState(() => _channelSnapshot = snapshot);
    } catch (error) {
      if (mounted) setState(() => _channelError = error);
    } finally {
      if (mounted) setState(() => _channelLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<MainDashboardData>(
    future: _resourcesFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return _DashboardMessage(
          title: 'Dashboard unavailable',
          message: '${snapshot.error}',
          action: OutlinedButton.icon(
            onPressed: () => setState(_reloadResources),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        );
      }
      final resources = snapshot.data!;
      final content = _DashboardScroll(
        children: [
          _buildObsSection(resources.obsConnections),
          const SizedBox(height: 8),
          _buildChannelAndPlanRow(resources),
          const SizedBox(height: 8),
          _buildQueueSection(resources.queues),
        ],
      );
      return AnimatedBuilder(
        animation: widget.providerEvents,
        child: content,
        builder: (context, child) {
          final runtime = widget.streamPlanRuntime;
          if (runtime == null) return child!;
          return AnimatedBuilder(
            animation: runtime,
            child: child,
            builder: (context, child) => child!,
          );
        },
      );
    },
  );

  Widget _buildObsSection(List<ResourceData> connections) {
    if (connections.isEmpty) {
      return _DashboardCard(
        icon: Icons.tv,
        iconColor: const Color(0xff256eff),
        title: 'OBS',
        child: Row(
          children: [
            const Expanded(
              child: Text(
                "ShowRunner can control OBS, but you haven't set up the connection yet.",
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: () => widget.onOpenWorkspace(6),
              child: const Text('Setup OBS'),
            ),
          ],
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final connection in connections)
          _ObsConnectionDashboardCard(
            connection: connection,
            registryFuture: widget.registryFuture,
            onOpenControls: () => widget.onOpenWorkspace(1),
            onEdit: () => widget.onOpenWorkspace(6),
          ),
      ],
    );
  }

  Widget _buildChannelAndPlanRow(MainDashboardData resources) {
    final twitch = _TwitchDashboardCard(
      settings: resources.twitchSettings,
      snapshot: _channelSnapshot,
      error: _channelError,
      loading: _channelLoading,
      providerEvents: widget.providerEvents,
      onRefresh: _refreshChannel,
      onOpen: () => widget.onOpenWorkspace(1),
    );
    final plan = _StreamPlanDashboardCard(
      plans: resources.streamPlans,
      runtime: widget.streamPlanRuntime,
      registryFuture: widget.registryFuture,
      onOpen: () => widget.onOpenWorkspace(6),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [twitch, const SizedBox(height: 8), plan],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: twitch),
            const SizedBox(width: 8),
            Expanded(child: plan),
          ],
        );
      },
    );
  }

  Widget _buildQueueSection(
    List<({String fileName, QueueConfig? config, Object? error})> queues,
  ) {
    final validQueues = queues.where((entry) => entry.config != null).toList();
    if (validQueues.isEmpty) {
      return _DashboardCard(
        icon: Icons.queue_music,
        title: 'Action queues',
        child: Row(
          children: [
            const Expanded(child: Text('No action queues configured.')),
            OutlinedButton(
              onPressed: () => widget.onOpenWorkspace(5),
              child: const Text('Open queues'),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in validQueues)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _QueueDashboardCard(
              name: entry.config!.name.isEmpty
                  ? entry.fileName
                  : entry.config!.name,
              queue: widget.actionQueue,
              configuredPaused: entry.config!.paused,
              onOpen: () => widget.onOpenWorkspace(5),
            ),
          ),
      ],
    );
  }
}

class _DashboardScroll extends StatelessWidget {
  const _DashboardScroll({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(12), children: children);
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({
    required this.icon,
    required this.title,
    required this.child,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final Widget child;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 6),
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    ),
  );
}

class _ObsConnectionDashboardCard extends StatelessWidget {
  const _ObsConnectionDashboardCard({
    required this.connection,
    required this.registryFuture,
    required this.onOpenControls,
    required this.onEdit,
  });

  final ResourceData connection;
  final Future<DartPluginRegistry> registryFuture;
  final VoidCallback onOpenControls;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 360,
    child: _DashboardCard(
      icon: Icons.tv,
      iconColor: const Color(0xff256eff),
      title: connection.name,
      child: FutureBuilder<bool>(
        future: registryFuture.then((registry) => registry.checkHealth('obs')),
        builder: (context, snapshot) {
          final healthy = snapshot.data == true;
          final checking = snapshot.connectionState == ConnectionState.waiting;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    checking
                        ? Icons.sync
                        : healthy
                        ? Icons.check_circle
                        : Icons.error_outline,
                    color: checking
                        ? null
                        : healthy
                        ? Colors.green
                        : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      checking
                          ? 'Checking connection...'
                          : healthy
                          ? 'Connected and responding.'
                          : 'Not connected or not configured.',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: onOpenControls,
                    child: const Text('Open OBS controls'),
                  ),
                  TextButton(onPressed: onEdit, child: const Text('Edit')),
                ],
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _TwitchDashboardCard extends StatelessWidget {
  const _TwitchDashboardCard({
    required this.settings,
    required this.snapshot,
    required this.error,
    required this.loading,
    required this.providerEvents,
    required this.onRefresh,
    required this.onOpen,
  });

  final Map<String, dynamic> settings;
  final TwitchChannelSnapshot? snapshot;
  final Object? error;
  final bool loading;
  final ProviderEventRuntime providerEvents;
  final VoidCallback onRefresh;
  final VoidCallback onOpen;

  bool get authenticated =>
      settings['accessToken']?.toString().trim().isNotEmpty == true &&
      settings['clientId']?.toString().trim().isNotEmpty == true &&
      settings['broadcasterId']?.toString().trim().isNotEmpty == true;

  @override
  Widget build(BuildContext context) => _DashboardCard(
    icon: Icons.live_tv,
    iconColor: const Color(0xff9147ff),
    title: 'Twitch',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!authenticated)
          _DashboardMessage(
            title: 'Twitch is not configured.',
            message:
                'Sign in and configure a broadcaster account to run the channel.',
            action: OutlinedButton(
              onPressed: onOpen,
              child: const Text('Open Twitch settings'),
            ),
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: _StatItem(
                  label: 'Channel',
                  value: snapshot?.broadcasterName.isNotEmpty == true
                      ? snapshot!.broadcasterName
                      : 'Configured',
                ),
              ),
              Expanded(
                child: _StatItem(
                  label: snapshot?.isLive == true ? 'LIVE' : 'Offline',
                  value: snapshot?.viewerCount?.toString() ?? '--',
                ),
              ),
              IconButton(
                tooltip: 'Refresh Twitch channel',
                onPressed: loading ? null : onRefresh,
                icon: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
          Text(
            providerEvents.twitchState.label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (error != null)
            Text(
              'Channel refresh failed: $error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ],
    ),
  );
}

class _StreamPlanDashboardCard extends StatefulWidget {
  const _StreamPlanDashboardCard({
    required this.plans,
    required this.runtime,
    required this.registryFuture,
    required this.onOpen,
  });

  final List<ResourceData> plans;
  final DartStreamPlanRuntime? runtime;
  final Future<DartPluginRegistry> registryFuture;
  final VoidCallback onOpen;

  @override
  State<_StreamPlanDashboardCard> createState() =>
      _StreamPlanDashboardCardState();
}

class _StreamPlanDashboardCardState extends State<_StreamPlanDashboardCard> {
  String? _selectedPlanId;
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _selectedPlanId = widget.plans.firstOrNull?.id;
  }

  ResourceData? get _selectedPlan {
    final id = _selectedPlanId;
    if (id == null) return null;
    return widget.plans.where((plan) => plan.id == id).firstOrNull;
  }

  @override
  void didUpdateWidget(covariant _StreamPlanDashboardCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final active = widget.runtime?.activePlanId;
    if (active != null && widget.plans.any((plan) => plan.id == active)) {
      _selectedPlanId = active;
    } else if (!widget.plans.any((plan) => plan.id == _selectedPlanId)) {
      _selectedPlanId = widget.plans.firstOrNull?.id;
    }
  }

  Future<void> _toggle() async {
    final runtime = widget.runtime;
    final plan = _selectedPlan;
    if (runtime == null || plan == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final registry = await widget.registryFuture;
      if (runtime.activePlanId == plan.id) {
        await runtime.deactivatePlan(registry: registry);
      } else {
        await runtime.activatePlan(
          plan.id,
          StreamPlanData.fromConfig(plan.config),
          registry: registry,
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _move(bool forward) async {
    final runtime = widget.runtime;
    final plan = _selectedPlan;
    if (runtime == null || plan == null || runtime.activePlanId != plan.id) {
      return;
    }
    try {
      final registry = await widget.registryFuture;
      if (forward) {
        await runtime.transitionToNextSegment(
          plan.id,
          StreamPlanData.fromConfig(plan.config),
          registry: registry,
        );
      } else {
        await runtime.transitionToPreviousSegment(
          plan.id,
          StreamPlanData.fromConfig(plan.config),
          registry: registry,
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final runtime = widget.runtime;
    final selected = _selectedPlan;
    final active = selected != null && runtime?.activePlanId == selected.id;
    return _DashboardCard(
      icon: Icons.view_agenda,
      title: 'Stream Plan',
      child: widget.plans.isEmpty
          ? Row(
              children: [
                const Expanded(child: Text('No stream plans configured.')),
                OutlinedButton(
                  onPressed: widget.onOpen,
                  child: const Text('Open resources'),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: selected?.id,
                        hint: const Text('Select a plan'),
                        items: [
                          for (final plan in widget.plans)
                            DropdownMenuItem(
                              value: plan.id,
                              child: Text(plan.name),
                            ),
                        ],
                        onChanged: active
                            ? null
                            : (value) =>
                                  setState(() => _selectedPlanId = value),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: active
                          ? 'Deactivate stream plan'
                          : 'Activate stream plan',
                      onPressed: _busy || selected == null ? null : _toggle,
                      icon: Icon(
                        active ? Icons.stop_circle : Icons.play_circle,
                      ),
                    ),
                  ],
                ),
                if (selected != null) ...[
                  Text(
                    active
                        ? 'Active${runtime?.activeSegmentId == null ? '' : ' · ${runtime!.activeSegmentId}'}'
                        : '${StreamPlanData.fromConfig(selected.config).segments.length} segments',
                  ),
                  if (active)
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Previous segment',
                          onPressed: () => _move(false),
                          icon: const Icon(Icons.skip_previous),
                        ),
                        IconButton(
                          tooltip: 'Next segment',
                          onPressed: () => _move(true),
                          icon: const Icon(Icons.skip_next),
                        ),
                      ],
                    ),
                ],
                if (_error != null)
                  Text(
                    'Stream Plan action failed: $_error',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
    );
  }
}

class _QueueDashboardCard extends StatelessWidget {
  const _QueueDashboardCard({
    required this.name,
    required this.queue,
    required this.configuredPaused,
    required this.onOpen,
  });

  final String name;
  final DartActionQueue queue;
  final bool configuredPaused;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => _DashboardCard(
    icon: Icons.queue_music,
    title: name,
    child: Row(
      children: [
        Expanded(
          child: Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              _StatItem(label: 'Pending', value: '${queue.pending.length}'),
              _StatItem(
                label: 'Running',
                value: queue.running == null ? '0' : '1',
              ),
              _StatItem(label: 'History', value: '${queue.history.length}'),
            ],
          ),
        ),
        Icon(
          configuredPaused ? Icons.pause_circle : Icons.play_circle,
          color: configuredPaused ? Colors.orange : Colors.green,
        ),
        IconButton(
          tooltip: 'Open queues',
          onPressed: onOpen,
          icon: const Icon(Icons.open_in_new),
        ),
      ],
    ),
  );
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(value, style: Theme.of(context).textTheme.titleMedium),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _DashboardMessage extends StatelessWidget {
  const _DashboardMessage({
    required this.title,
    required this.message,
    this.action,
  });

  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Padding(
        padding: EdgeInsets.only(top: 2),
        child: Icon(Icons.warning_amber, color: Colors.orange),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            const SizedBox(height: 4),
            Text(message),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    ],
  );
}
