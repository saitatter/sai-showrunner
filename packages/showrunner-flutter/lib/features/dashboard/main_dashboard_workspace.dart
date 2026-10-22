import '../../runtime/automation_queue_manager.dart';
import '../../design_system/workspace_notice.dart';
import '../../plugins/twitch/ui/twitch_channel_view_controller.dart';
import 'dashboard_widgets.dart';
import 'obs_dashboard_card.dart';
import 'twitch_dashboard_card.dart';
import 'stream_plan_dashboard_card.dart';
import 'queue_dashboard_card.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/brand_icons.dart';
import '../../plugins/registry/plugin_registry.dart';
import '../../plugins/runtime/provider_event_workers.dart';
import '../../plugins/stream_plans/manifest.dart';
import '../../plugins/twitch/channel_runtime.dart';
import '../../runtime/action_queue.dart';
import '../../schema/queue.dart';
import '../../schema/resource.dart';
import '../../services/showrunner_data_service.dart';
import '../../plugins/twitch/account_runtime.dart';
import '../../app/workspace_registry.dart';

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
    this.queueManager,
    required this.onOpenWorkspace,
    this.resourcesLoader,
  });

  final ShowRunnerDataService dataService;
  final DartActionQueue actionQueue;
  final DartAutomationQueueManager? queueManager;
  final ProviderEventRuntime providerEvents;
  final Future<DartPluginRegistry> registryFuture;
  final DartStreamPlanRuntime? streamPlanRuntime;
  final ValueChanged<WorkspaceId> onOpenWorkspace;
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
  late TwitchChannelViewController _channel;

  @override
  void initState() {
    super.initState();
    _reloadResources();
    _installChannel();
  }

  void _reloadResources() {
    _resourcesFuture = widget.resourcesLoader?.call() ?? _loadResources();
  }

  Future<MainDashboardData> _loadResources() async {
    final results = await Future.wait<Object>([
      widget.dataService.storage
          .resource(const ResourceTypeId('OBSConnection'))
          .list(),
      widget.dataService.storage.queueConfigs.list(),
      widget.dataService.storage
          .resource(const ResourceTypeId('StreamPlan'))
          .list(),
      loadTwitchChannelSettings(widget.dataService),
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

  void _installChannel() {
    final service = TwitchChannelInfoService(dataService: widget.dataService);
    _channel = TwitchChannelViewController(load: service.load);
  }

  @override
  void didUpdateWidget(MainDashboardWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataService != widget.dataService ||
        oldWidget.resourcesLoader != widget.resourcesLoader) {
      _reloadResources();
    }
    if (oldWidget.dataService.userDirectory.absolute.path !=
        widget.dataService.userDirectory.absolute.path) {
      _channel.dispose();
      _installChannel();
    }
  }

  @override
  void dispose() {
    _channel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<MainDashboardData>(
    future: _resourcesFuture,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return WorkspaceNotice(
          title: 'Dashboard unavailable',
          message:
              'Dashboard resources could not be loaded. Check storage access and retry.',
          action: OutlinedButton.icon(
            onPressed: () => setState(_reloadResources),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        );
      }
      final resources = snapshot.data!;
      final content = DashboardScroll(
        children: [
          _buildObsSection(resources.obsConnections),
          const SizedBox(height: 8),
          _buildChannelAndPlanRow(resources),
          const SizedBox(height: 8),
          _buildQueueSection(resources.queues),
        ],
      );
      return content;
    },
  );

  Widget _buildObsSection(List<ResourceData> connections) {
    if (connections.isEmpty) {
      return DashboardCard(
        iconWidget: const ObsBrandIcon(size: 18),
        title: 'OBS',
        child: WorkspaceNotice(
          message:
              "ShowRunner can control OBS, but you haven't set up the connection yet.",
          icon: Icons.warning_amber,
          color: const Color(0xffffb74d),
          action: FilledButton(
            onPressed: () => widget.onOpenWorkspace(WorkspaceIds.resources),
            child: const Text('Setup OBS'),
          ),
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final connection in connections)
          ObsConnectionDashboardCard(
            connection: connection,
            registryFuture: widget.registryFuture,
            onOpenControls: () => widget.onOpenWorkspace(WorkspaceIds.plugins),
            onEdit: () => widget.onOpenWorkspace(WorkspaceIds.resources),
          ),
      ],
    );
  }

  Widget _buildChannelAndPlanRow(MainDashboardData resources) {
    final twitch = ValueListenableBuilder<TwitchChannelView>(
      valueListenable: _channel,
      builder: (context, view, _) => TwitchDashboardCard(
        key: ValueKey(widget.dataService.userDirectory.absolute.path),
        settings: resources.twitchSettings,
        dataService: widget.dataService,
        registryFuture: widget.registryFuture,
        snapshot: view.snapshot,
        error: view.failed
            ? 'Channel details could not be refreshed. Check the connection and retry.'
            : null,
        loading: view.loading,
        providerEvents: widget.providerEvents,
        onRefresh: _channel.refresh,
      ),
    );
    final plan = StreamPlanDashboardCard(
      plans: resources.streamPlans,
      runtime: widget.streamPlanRuntime,
      registryFuture: widget.registryFuture,
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
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in validQueues)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: QueueDashboardCard(
              name: entry.config!.name.isEmpty
                  ? entry.fileName
                  : entry.config!.name,
              queue: widget.actionQueue,
              queueManager: widget.queueManager,
              queueId: entry.fileName,
              onOpen: () => widget.onOpenWorkspace(WorkspaceIds.queues),
            ),
          ),
      ],
    );
  }
}
