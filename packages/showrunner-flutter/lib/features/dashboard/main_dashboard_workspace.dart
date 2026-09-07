import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../design_system/brand_icons.dart';
import '../../design_system/tokens/tokens.dart';
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
    required this.onOpenWorkspace,
    this.resourcesLoader,
  });

  final ShowRunnerDataService dataService;
  final DartActionQueue actionQueue;
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
        iconWidget: const ObsBrandIcon(size: 18),
        title: 'OBS',
        child: _DashboardMessage(
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
          _ObsConnectionDashboardCard(
            connection: connection,
            registryFuture: widget.registryFuture,
            onOpenControls: () => widget.onOpenWorkspace(WorkspaceIds.plugins),
            onEdit: () => widget.onOpenWorkspace(WorkspaceIds.resources),
          ),
      ],
    );
  }

  Widget _buildChannelAndPlanRow(MainDashboardData resources) {
    final twitch = _TwitchDashboardCard(
      settings: resources.twitchSettings,
      dataService: widget.dataService,
      registryFuture: widget.registryFuture,
      snapshot: _channelSnapshot,
      error: _channelError,
      loading: _channelLoading,
      providerEvents: widget.providerEvents,
      onRefresh: _refreshChannel,
    );
    final plan = _StreamPlanDashboardCard(
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
            child: _QueueDashboardCard(
              name: entry.config!.name.isEmpty
                  ? entry.fileName
                  : entry.config!.name,
              queue: widget.actionQueue,
              configuredPaused: entry.config!.paused,
              onOpen: () => widget.onOpenWorkspace(WorkspaceIds.queues),
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
    required this.title,
    required this.child,
    this.icon,
    this.iconWidget,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final Widget? iconWidget;

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
              iconWidget ?? Icon(icon, size: 18),
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
      iconWidget: const ObsBrandIcon(size: 18),
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

class _TwitchDashboardCard extends StatefulWidget {
  const _TwitchDashboardCard({
    required this.settings,
    required this.dataService,
    required this.registryFuture,
    required this.snapshot,
    required this.error,
    required this.loading,
    required this.providerEvents,
    required this.onRefresh,
  });

  final Map<String, dynamic> settings;
  final ShowRunnerDataService dataService;
  final Future<DartPluginRegistry> registryFuture;
  final TwitchChannelSnapshot? snapshot;
  final Object? error;
  final bool loading;
  final ProviderEventRuntime providerEvents;
  final Future<void> Function() onRefresh;

  @override
  State<_TwitchDashboardCard> createState() => _TwitchDashboardCardState();
}

class _TwitchDashboardCardState extends State<_TwitchDashboardCard> {
  late final TwitchAccountAuthService _accountAuthService;
  late final TextEditingController _titleController;
  late final TextEditingController _categoryController;
  late final FocusNode _titleFocus;
  late final FocusNode _categoryFocus;
  Future<List<ResourceData?>>? _accountsFuture;
  final _tags = <String>[];
  String? _categoryId;
  String? _accountBusy;
  Object? _accountError;
  Object? _streamInfoError;
  bool _savingStreamInfo = false;

  @override
  void initState() {
    super.initState();
    _accountAuthService = TwitchAccountAuthService(
      dataService: widget.dataService,
    );
    _titleController = TextEditingController();
    _categoryController = TextEditingController();
    _titleFocus = FocusNode();
    _categoryFocus = FocusNode();
    _syncSnapshot(widget.snapshot);
    _reloadAccounts();
  }

  @override
  void didUpdateWidget(covariant _TwitchDashboardCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot != widget.snapshot) {
      _syncSnapshot(widget.snapshot);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _categoryController.dispose();
    _titleFocus.dispose();
    _categoryFocus.dispose();
    super.dispose();
  }

  void _syncSnapshot(TwitchChannelSnapshot? snapshot) {
    if (snapshot == null) return;
    if (!_titleFocus.hasFocus) {
      _titleController.text = snapshot.channelTitle;
    }
    if (!_categoryFocus.hasFocus) {
      _categoryController.text = snapshot.categoryName;
      _categoryId = snapshot.categoryId;
    }
    if (!_categoryFocus.hasFocus && snapshot.tags.isNotEmpty) {
      _tags
        ..clear()
        ..addAll(snapshot.tags);
    }
  }

  void _reloadAccounts() {
    final future = Future.wait([
      _accountAuthService.loadAccount('channel'),
      _accountAuthService.loadAccount('bot'),
    ]);
    if (mounted) {
      setState(() {
        _accountsFuture = future;
      });
    } else {
      _accountsFuture = future;
    }
  }

  bool _accountAuthenticated(ResourceData? account) {
    final config = account?.config ?? const <String, dynamic>{};
    return config['accessToken']?.toString().trim().isNotEmpty == true &&
        config['twitchId']?.toString().trim().isNotEmpty == true;
  }

  Future<void> _signIn(String accountId) async {
    setState(() {
      _accountBusy = accountId;
      _accountError = null;
    });
    try {
      await _accountAuthService.authorizeAccount(accountId);
      _reloadAccounts();
      if (accountId == 'channel') await widget.onRefresh();
    } catch (error) {
      if (mounted) setState(() => _accountError = error);
    } finally {
      if (mounted) setState(() => _accountBusy = null);
    }
  }

  Future<void> _saveStreamInfo() async {
    setState(() {
      _savingStreamInfo = true;
      _streamInfoError = null;
    });
    try {
      final settings = await loadTwitchChannelSettings(widget.dataService);
      final registry = await widget.registryFuture;
      await registry.invokeAction('twitch', 'setStreamInfo', {
        'broadcasterId': settings['broadcasterId'],
        if (_titleController.text.trim().isNotEmpty)
          'title': _titleController.text.trim(),
        if (_categoryController.text.trim().isNotEmpty)
          'categoryId': _categoryId ?? _categoryController.text.trim(),
        if (_tags.isNotEmpty) 'tags': List<String>.from(_tags),
      });
      await widget.onRefresh();
    } catch (error) {
      if (mounted) setState(() => _streamInfoError = error);
    } finally {
      if (mounted) setState(() => _savingStreamInfo = false);
    }
  }

  Future<void> _addTag() async {
    final controller = TextEditingController();
    try {
      final tag = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Add Twitch tag'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Tag'),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Add'),
            ),
          ],
        ),
      );
      final normalized = tag?.trim() ?? '';
      if (normalized.isNotEmpty && mounted && !_tags.contains(normalized)) {
        setState(() => _tags.add(normalized));
      }
    } finally {
      controller.dispose();
    }
  }

  bool _channelConfigured(ResourceData? account) =>
      _accountAuthenticated(account) ||
      (widget.settings['accessToken']?.toString().trim().isNotEmpty == true &&
          widget.settings['broadcasterId']?.toString().trim().isNotEmpty ==
              true);

  bool _botConfigured(ResourceData? account) =>
      _accountAuthenticated(account) ||
      widget.settings['moderatorId']?.toString().trim().isNotEmpty == true;

  @override
  Widget build(BuildContext context) => _DashboardCard(
    iconWidget: const TwitchBrandIcon(size: 18),
    title: 'Twitch',
    child: FutureBuilder<List<ResourceData?>>(
      future: _accountsFuture,
      builder: (context, snapshot) {
        final accounts = snapshot.data ?? const <ResourceData?>[null, null];
        final channelConfigured = _channelConfigured(
          accounts.isNotEmpty ? accounts[0] : null,
        );
        final botConfigured = _botConfigured(
          accounts.length > 1 ? accounts[1] : null,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_accountError != null)
              _DashboardMessage(
                message: 'Twitch sign-in failed: $_accountError',
                icon: Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
              ),
            if (!channelConfigured)
              _DashboardMessage(
                message: 'ShowRunner needs your Twitch account to run',
                icon: Icons.cancel_outlined,
                color: Theme.of(context).colorScheme.error,
                action: _accountButton(
                  context,
                  accountId: 'channel',
                  label: 'Sign into Channel',
                ),
              ),
            if (!botConfigured)
              _DashboardMessage(
                message:
                    'ShowRunner needs a bot account to run. You can use a separate bot account or just sign into your channel again.',
                icon: Icons.cancel_outlined,
                color: Theme.of(context).colorScheme.error,
                action: _accountButton(
                  context,
                  accountId: 'bot',
                  label: 'Sign into Bot',
                ),
              ),
            if (channelConfigured) _buildChannelStats(context),
            _buildStreamInfo(context),
          ],
        );
      },
    ),
  );

  Widget _accountButton(
    BuildContext context, {
    required String accountId,
    required String label,
  }) {
    final busy = _accountBusy == accountId;
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: Theme.of(context).colorScheme.error,
        foregroundColor: Theme.of(context).colorScheme.onError,
      ),
      onPressed: busy ? null : () => _signIn(accountId),
      child: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    );
  }

  Widget _buildChannelStats(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: _StatItem(
            label: 'Channel',
            value: widget.snapshot?.broadcasterName.isNotEmpty == true
                ? widget.snapshot!.broadcasterName
                : 'Configured',
          ),
        ),
        Expanded(
          child: _StatItem(
            label: widget.snapshot?.isLive == true ? 'LIVE' : 'Offline',
            value: widget.snapshot?.viewerCount?.toString() ?? '--',
          ),
        ),
        IconButton(
          tooltip: 'Refresh Twitch channel',
          onPressed: widget.loading ? null : () => widget.onRefresh(),
          icon: widget.loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
        ),
      ],
    ),
  );

  Widget _buildStreamInfo(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _titleController,
        focusNode: _titleFocus,
        decoration: const InputDecoration(labelText: 'Title'),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _categoryController,
        focusNode: _categoryFocus,
        decoration: const InputDecoration(labelText: 'Category'),
      ),
      if (_tags.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final tag in _tags)
              InputChip(
                label: Text(tag),
                onDeleted: () => setState(() => _tags.remove(tag)),
              ),
          ],
        ),
      ],
      const SizedBox(height: 8),
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
          foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        onPressed: _addTag,
        child: const Text('Add Tag'),
      ),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: _savingStreamInfo ? null : _saveStreamInfo,
          child: _savingStreamInfo
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ),
      if (_streamInfoError != null)
        Text(
          'Failed to update Twitch info: $_streamInfoError',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (widget.error != null)
        Text(
          'Channel refresh failed: ${widget.error}',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      Text(
        widget.providerEvents.twitchState.label,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

class _StreamPlanDashboardCard extends StatefulWidget {
  const _StreamPlanDashboardCard({
    required this.plans,
    required this.runtime,
    required this.registryFuture,
  });

  final List<ResourceData> plans;
  final DartStreamPlanRuntime? runtime;
  final Future<DartPluginRegistry> registryFuture;

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
      icon: mdiIcon(0xF00F0),
      title: 'Stream Plan',
      child: SizedBox(
        height: 292,
        child: Column(
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
                    onChanged: widget.plans.isEmpty || active
                        ? null
                        : (value) => setState(() => _selectedPlanId = value),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: active
                      ? 'Deactivate stream plan'
                      : 'Activate stream plan',
                  onPressed: _busy || selected == null ? null : _toggle,
                  icon: Icon(active ? Icons.stop_circle : Icons.play_circle),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: ShowRunnerColors.surfaceBorder),
                  borderRadius: BorderRadius.circular(4),
                ),
                padding: const EdgeInsets.all(4),
                child: selected == null
                    ? const SizedBox.expand()
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final segment in StreamPlanData.fromConfig(
                              selected.config,
                            ).segments)
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: Chip(label: Text(segment.name)),
                              ),
                          ],
                        ),
                      ),
              ),
            ),
            if (selected != null) ...[
              const SizedBox(height: 4),
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
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
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
    required this.message,
    this.title,
    this.action,
    this.icon = Icons.warning_amber,
    this.color = Colors.orange,
  });

  final String message;
  final String? title;
  final Widget? action;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: title == null
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              if (title != null) ...[Text(title!), const SizedBox(height: 4)],
              Text(message, textAlign: title == null ? TextAlign.center : null),
            ],
          ),
        ),
        if (action != null) ...[const SizedBox(width: 12), action!],
      ],
    ),
  );
}
