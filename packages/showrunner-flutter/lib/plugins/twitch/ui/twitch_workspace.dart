import 'dart:async';

import 'package:flutter/material.dart';

import '../../registry/plugin_registry.dart';
import '../../runtime/provider_event_workers.dart';
import '../../../runtime/expression.dart';
import '../../../services/showrunner_data_service.dart';
import '../../../features/resources/duration_field.dart';
import '../channel_runtime.dart';
import '../channel_points.dart';

class TwitchWorkspace extends StatefulWidget {
  const TwitchWorkspace({
    super.key,
    required this.providerEvents,
    required this.registryFuture,
    required this.dataService,
  });

  final ProviderEventRuntime providerEvents;
  final Future<DartPluginRegistry> registryFuture;
  final ShowRunnerDataService dataService;

  @override
  State<TwitchWorkspace> createState() => _TwitchWorkspaceState();
}

class _TwitchWorkspaceState extends State<TwitchWorkspace> {
  StreamSubscription<RuntimeMap>? _chatSubscription;
  String? _latestMessage;
  String? _latestAuthor;
  final _messageHistory = <String>[];
  late final TextEditingController _messageController;
  late final TextEditingController _markerController;
  late final TextEditingController _viewerController;
  late final TextEditingController _reasonController;
  late final TextEditingController _streamTitleController;
  late final TextEditingController _categoryController;
  late final TextEditingController _tagsController;
  late final TextEditingController _predictionTitleController;
  late final TextEditingController _predictionOutcomesController;
  late final TextEditingController _pollTitleController;
  late final TextEditingController _pollChoicesController;
  late final TextEditingController _announcementController;
  late final TextEditingController _shoutoutController;
  late final TextEditingController _raidTargetController;
  late final TwitchChannelInfoService _channelInfoService;
  late final TwitchChannelPointService _channelPointService;
  TwitchChannelSnapshot? _channelSnapshot;
  Future<List<TwitchChannelPointReward>>? _rewardsFuture;
  Object? _channelInfoError;
  bool _channelInfoLoading = true;
  int _timeoutSeconds = 60;
  int _adDuration = 30;
  int _predictionDuration = 30;
  int _pollDuration = 30;
  String _announcementColor = 'primary';
  Object? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _messageController = TextEditingController();
    _markerController = TextEditingController();
    _viewerController = TextEditingController();
    _reasonController = TextEditingController();
    _streamTitleController = TextEditingController();
    _categoryController = TextEditingController();
    _tagsController = TextEditingController();
    _predictionTitleController = TextEditingController();
    _predictionOutcomesController = TextEditingController();
    _pollTitleController = TextEditingController();
    _pollChoicesController = TextEditingController();
    _announcementController = TextEditingController();
    _shoutoutController = TextEditingController();
    _raidTargetController = TextEditingController();
    _channelInfoService = TwitchChannelInfoService(
      dataService: widget.dataService,
    );
    _channelPointService = TwitchChannelPointService(
      dataService: widget.dataService,
    );
    unawaited(_refreshChannelInfo());
    _reloadRewards();
    _chatSubscription = widget.providerEvents.eventHub.stream('chat').listen((
      event,
    ) {
      if (!mounted) return;
      setState(() {
        _latestAuthor = event['chatter_user_name']?.toString();
        _latestMessage = event['message']?.toString();
        _messageHistory.insert(
          0,
          '${_latestAuthor ?? 'Unknown'}: ${_latestMessage ?? 'Empty message'}',
        );
        if (_messageHistory.length > 20) _messageHistory.removeLast();
      });
    });
  }

  @override
  void dispose() {
    unawaited(_chatSubscription?.cancel());
    _messageController.dispose();
    _markerController.dispose();
    _viewerController.dispose();
    _reasonController.dispose();
    _streamTitleController.dispose();
    _categoryController.dispose();
    _tagsController.dispose();
    _predictionTitleController.dispose();
    _predictionOutcomesController.dispose();
    _pollTitleController.dispose();
    _pollChoicesController.dispose();
    _announcementController.dispose();
    _shoutoutController.dispose();
    _raidTargetController.dispose();
    super.dispose();
  }

  Future<void> _invoke(String actionId, RuntimeMap config) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final registry = await widget.registryFuture;
      final settings = await widget.dataService.loadPluginSettings('twitch');
      await registry.invokeAction('twitch', actionId, {
        ...config,
        'broadcasterId': settings['broadcasterId'],
        'moderatorId': settings['moderatorId'],
      });
    } catch (error) {
      _error = error;
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _toggleTwitch(bool connect) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (connect) {
        await widget.providerEvents.startTwitch();
      } else {
        await widget.providerEvents.stopTwitch();
      }
    } catch (error) {
      _error = error;
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _refreshChannelInfo() async {
    if (mounted) {
      setState(() {
        _channelInfoLoading = true;
        _channelInfoError = null;
      });
    }
    try {
      final snapshot = await _channelInfoService.load();
      if (mounted) setState(() => _channelSnapshot = snapshot);
    } catch (error) {
      if (mounted) setState(() => _channelInfoError = error);
    } finally {
      if (mounted) setState(() => _channelInfoLoading = false);
    }
  }

  void _reloadRewards() {
    _rewardsFuture = _channelPointService.list();
    if (mounted) setState(() {});
  }

  Future<void> _createReward() async {
    final draft = await showDialog<TwitchChannelPointRewardDraft>(
      context: context,
      builder: (context) => const _ChannelPointRewardDialog(),
    );
    if (draft == null || !mounted) return;
    await _runRewardOperation(() => _channelPointService.create(draft));
  }

  Future<void> _editReward(TwitchChannelPointReward reward) async {
    final draft = await showDialog<TwitchChannelPointRewardDraft>(
      context: context,
      builder: (context) => _ChannelPointRewardDialog(reward: reward),
    );
    if (draft == null || !mounted) return;
    await _runRewardOperation(
      () => _channelPointService.update(reward.id, draft),
    );
  }

  Future<void> _deleteReward(TwitchChannelPointReward reward) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete channel point reward?'),
        content: Text('Delete “${reward.title}” from Twitch?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _runRewardOperation(() => _channelPointService.delete(reward.id));
  }

  Future<void> _runRewardOperation(Future<Object?> Function() operation) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
      _reloadRewards();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.providerEvents,
    builder: (context, _) => ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Twitch', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('EventSub connection and chat activity.'),
        const SizedBox(height: 24),
        FutureBuilder<bool>(
          future: widget.registryFuture.then(
            (registry) => registry.checkHealth('twitch'),
          ),
          builder: (context, snapshot) {
            final state = widget.providerEvents.twitchState;
            final running = state == ProviderWorkerState.running;
            final reconnecting = state == ProviderWorkerState.reconnecting;
            final statusIcon = switch (state) {
              ProviderWorkerState.starting => Icons.sync,
              ProviderWorkerState.running => Icons.check_circle,
              ProviderWorkerState.reconnecting => Icons.sync_problem,
              ProviderWorkerState.error => Icons.error_outline,
              ProviderWorkerState.stopped => Icons.pause_circle,
            };
            final statusColor = switch (state) {
              ProviderWorkerState.running => Colors.green,
              ProviderWorkerState.reconnecting => Colors.orange,
              ProviderWorkerState.error => Theme.of(context).colorScheme.error,
              _ => null,
            };
            final statusText = switch (state) {
              ProviderWorkerState.starting => 'Starting EventSub connection...',
              ProviderWorkerState.running => 'Running',
              ProviderWorkerState.reconnecting =>
                'Reconnecting (attempt ${widget.providerEvents.twitchReconnectAttempts})',
              ProviderWorkerState.error =>
                'Error: ${widget.providerEvents.twitchLastError ?? 'Connection failed.'}',
              ProviderWorkerState.stopped =>
                snapshot.hasError
                    ? 'Not configured: ${snapshot.error}'
                    : 'Stopped or not configured.',
            };
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(statusIcon, color: statusColor),
                      title: const Text('EventSub'),
                      subtitle: Text(statusText),
                    ),
                    if (widget
                        .providerEvents
                        .twitchSubscriptionErrors
                        .isNotEmpty)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: const Icon(
                          Icons.warning_amber,
                          color: Colors.orange,
                        ),
                        title: const Text('Some event types are unavailable'),
                        subtitle: Text(
                          widget.providerEvents.twitchSubscriptionErrors.join(
                            '\n',
                          ),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton.icon(
                        onPressed:
                            _busy || state == ProviderWorkerState.starting
                            ? null
                            : reconnecting
                            ? null
                            : running
                            ? () => _toggleTwitch(false)
                            : () => _toggleTwitch(true),
                        icon: Icon(
                          running
                              ? Icons.stop_circle_outlined
                              : Icons.play_circle_outline,
                        ),
                        label: Text(
                          running
                              ? 'Disconnect EventSub'
                              : reconnecting
                              ? 'Reconnecting EventSub'
                              : state == ProviderWorkerState.starting
                              ? 'Starting EventSub'
                              : 'Connect EventSub',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _buildChannelSnapshot(context),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _buildChannelPointRewards(context),
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.chat_bubble_outline),
            title: Text(_latestMessage ?? 'No Twitch chat messages yet'),
            subtitle: Text(_latestAuthor ?? 'Latest Twitch message'),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Channel controls',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _messageController,
                  decoration: const InputDecoration(labelText: 'Chat message'),
                  onChanged: (_) => setState(() {}),
                ),
                FilledButton.icon(
                  onPressed: _busy || _messageController.text.trim().isEmpty
                      ? null
                      : () => _invoke('chat', {
                          'message': _messageController.text.trim(),
                        }),
                  icon: const Icon(Icons.send),
                  label: const Text('Send chat'),
                ),
                TextField(
                  controller: _markerController,
                  decoration: const InputDecoration(
                    labelText: 'Marker comment',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || _markerController.text.trim().isEmpty
                      ? null
                      : () => _invoke('streamMarker', {
                          'markerName': _markerController.text.trim(),
                        }),
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Place marker'),
                ),
                TextField(
                  controller: _viewerController,
                  decoration: const InputDecoration(labelText: 'Viewer ID'),
                  onChanged: (_) => setState(() {}),
                ),
                DurationValueField(
                  label: 'Timeout duration',
                  initialSeconds: _timeoutSeconds,
                  onChanged: (seconds) =>
                      setState(() => _timeoutSeconds = seconds),
                ),
                TextField(
                  controller: _reasonController,
                  decoration: const InputDecoration(labelText: 'Reason'),
                  onChanged: (_) => setState(() {}),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy || _viewerController.text.trim().isEmpty
                          ? null
                          : () => _invoke('timeout', {
                              'viewerId': _viewerController.text.trim(),
                              'duration': _timeoutSeconds,
                              if (_reasonController.text.trim().isNotEmpty)
                                'reason': _reasonController.text.trim(),
                            }),
                      icon: const Icon(Icons.timer_outlined),
                      label: const Text('Timeout'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy || _viewerController.text.trim().isEmpty
                          ? null
                          : () => _invoke('ban', {
                              'viewerId': _viewerController.text.trim(),
                              if (_reasonController.text.trim().isNotEmpty)
                                'reason': _reasonController.text.trim(),
                            }),
                      icon: const Icon(Icons.block),
                      label: const Text('Ban'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy || _viewerController.text.trim().isEmpty
                          ? null
                          : () => _invoke('unban', {
                              'viewerId': _viewerController.text.trim(),
                            }),
                      icon: const Icon(Icons.lock_open_outlined),
                      label: const Text('Unban'),
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
                  'Stream controls',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _streamTitleController,
                  decoration: const InputDecoration(labelText: 'Stream title'),
                  onChanged: (_) => setState(() {}),
                ),
                TextField(
                  controller: _categoryController,
                  decoration: const InputDecoration(labelText: 'Category ID'),
                  onChanged: (_) => setState(() {}),
                ),
                TextField(
                  controller: _tagsController,
                  decoration: const InputDecoration(labelText: 'Tags'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed:
                          _busy ||
                              (_streamTitleController.text.trim().isEmpty &&
                                  _categoryController.text.trim().isEmpty &&
                                  _tagsController.text.trim().isEmpty)
                          ? null
                          : () => _invoke('setStreamInfo', {
                              if (_streamTitleController.text.trim().isNotEmpty)
                                'title': _streamTitleController.text.trim(),
                              if (_categoryController.text.trim().isNotEmpty)
                                'categoryId': _categoryController.text.trim(),
                              if (_tagsController.text.trim().isNotEmpty)
                                'tags': _commaSeparated(_tagsController.text),
                            }),
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Update stream info'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _invoke('createClip', const {}),
                      icon: const Icon(Icons.content_cut),
                      label: const Text('Create clip'),
                    ),
                    SizedBox(
                      width: 180,
                      child: DropdownButtonFormField<int>(
                        initialValue: _adDuration,
                        decoration: const InputDecoration(
                          labelText: 'Ad duration',
                        ),
                        items: [30, 60, 90, 120, 150, 180]
                            .map(
                              (seconds) => DropdownMenuItem(
                                value: seconds,
                                child: Text('$seconds seconds'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _adDuration = value);
                          }
                        },
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _invoke('runAd', {'duration': _adDuration}),
                      icon: const Icon(Icons.ads_click),
                      label: const Text('Run ad'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _invoke('snoozeAds', const {}),
                      icon: const Icon(Icons.notifications_off_outlined),
                      label: const Text('Snooze ads'),
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
                  'Polls and predictions',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _predictionTitleController,
                  decoration: const InputDecoration(
                    labelText: 'Prediction title',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                TextField(
                  controller: _predictionOutcomesController,
                  decoration: const InputDecoration(
                    labelText: 'Prediction outcomes',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                DurationValueField(
                  label: 'Prediction duration',
                  initialSeconds: _predictionDuration,
                  onChanged: (seconds) =>
                      setState(() => _predictionDuration = seconds),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _busy ||
                          _predictionTitleController.text.trim().isEmpty ||
                          _commaSeparated(
                                _predictionOutcomesController.text,
                              ).length <
                              2
                      ? null
                      : () => _invoke('createPrediction', {
                          'title': _predictionTitleController.text.trim(),
                          'duration': _predictionDuration,
                          'outcomes': _commaSeparated(
                            _predictionOutcomesController.text,
                          ),
                        }),
                  icon: const Icon(Icons.casino_outlined),
                  label: const Text('Create prediction'),
                ),
                const Divider(height: 24),
                TextField(
                  controller: _pollTitleController,
                  decoration: const InputDecoration(labelText: 'Poll title'),
                  onChanged: (_) => setState(() {}),
                ),
                TextField(
                  controller: _pollChoicesController,
                  decoration: const InputDecoration(labelText: 'Poll choices'),
                  onChanged: (_) => setState(() {}),
                ),
                DurationValueField(
                  label: 'Poll duration',
                  initialSeconds: _pollDuration,
                  onChanged: (seconds) =>
                      setState(() => _pollDuration = seconds),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _busy ||
                          _pollTitleController.text.trim().isEmpty ||
                          _commaSeparated(_pollChoicesController.text).length <
                              2
                      ? null
                      : () => _invoke('createPoll', {
                          'title': _pollTitleController.text.trim(),
                          'duration': _pollDuration,
                          'choices': _commaSeparated(
                            _pollChoicesController.text,
                          ),
                        }),
                  icon: const Icon(Icons.poll_outlined),
                  label: const Text('Create poll'),
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
                  'Community actions',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _announcementController,
                  decoration: const InputDecoration(labelText: 'Announcement'),
                  onChanged: (_) => setState(() {}),
                ),
                DropdownButtonFormField<String>(
                  initialValue: _announcementColor,
                  decoration: const InputDecoration(
                    labelText: 'Announcement color',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'primary', child: Text('Primary')),
                    DropdownMenuItem(value: 'blue', child: Text('Blue')),
                    DropdownMenuItem(value: 'green', child: Text('Green')),
                    DropdownMenuItem(value: 'orange', child: Text('Orange')),
                    DropdownMenuItem(value: 'purple', child: Text('Purple')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _announcementColor = value);
                    }
                  },
                ),
                OutlinedButton.icon(
                  onPressed:
                      _busy || _announcementController.text.trim().isEmpty
                      ? null
                      : () => _invoke('announcement', {
                          'message': _announcementController.text.trim(),
                          'color': _announcementColor,
                        }),
                  icon: const Icon(Icons.campaign_outlined),
                  label: const Text('Make announcement'),
                ),
                TextField(
                  controller: _shoutoutController,
                  decoration: const InputDecoration(labelText: 'Streamer ID'),
                  onChanged: (_) => setState(() {}),
                ),
                OutlinedButton.icon(
                  onPressed: _busy || _shoutoutController.text.trim().isEmpty
                      ? null
                      : () => _invoke('shoutout', {
                          'streamer': _shoutoutController.text.trim(),
                        }),
                  icon: const Icon(Icons.campaign),
                  label: const Text('Shoutout'),
                ),
                TextField(
                  controller: _raidTargetController,
                  decoration: const InputDecoration(
                    labelText: 'Raid target ID',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed:
                          _busy || _raidTargetController.text.trim().isEmpty
                          ? null
                          : () => _invoke('startRaid', {
                              'target': _raidTargetController.text.trim(),
                            }),
                      icon: const Icon(Icons.celebration_outlined),
                      label: const Text('Start raid'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _invoke('cancelRaid', const {}),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Cancel raid'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_error != null)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('Twitch action error'),
              subtitle: Text('$_error'),
            ),
          ),
        if (_messageHistory.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Activity', style: Theme.of(context).textTheme.titleLarge),
          ..._messageHistory.map(
            (message) => ListTile(
              dense: true,
              leading: const Icon(Icons.chat_outlined),
              title: Text(message),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _buildChannelPointRewards(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Text(
            'Channel point rewards',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Refresh channel point rewards',
            onPressed: _busy ? null : _reloadRewards,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Create channel point reward',
            onPressed: _busy ? null : _createReward,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      const Text(
        'Manage rewards through Twitch. Existing ShowRunner resource files remain available in Resources.',
      ),
      const SizedBox(height: 8),
      FutureBuilder<List<TwitchChannelPointReward>>(
        future: _rewardsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LinearProgressIndicator();
          }
          if (snapshot.hasError) {
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.warning_amber),
              title: const Text('Rewards unavailable'),
              subtitle: Text('${snapshot.error}'),
            );
          }
          final rewards = snapshot.data ?? const [];
          if (rewards.isEmpty) {
            return const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.card_giftcard_outlined),
              title: Text('No channel point rewards found'),
            );
          }
          return Column(
            children: [
              for (final reward in rewards)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    reward.isEnabled
                        ? Icons.card_giftcard
                        : Icons.card_giftcard_outlined,
                    color: reward.isEnabled ? Colors.green : null,
                  ),
                  title: Text(reward.title),
                  subtitle: Text(
                    '${reward.cost} points${reward.prompt.isEmpty ? '' : ' · ${reward.prompt}'}',
                  ),
                  trailing: Wrap(
                    spacing: 0,
                    children: [
                      IconButton(
                        tooltip: 'Edit reward',
                        onPressed: _busy ? null : () => _editReward(reward),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Delete reward',
                        onPressed: _busy ? null : () => _deleteReward(reward),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );

  Widget _buildChannelSnapshot(BuildContext context) {
    final snapshot = _channelSnapshot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Channel and stream',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Spacer(),
            IconButton(
              tooltip: 'Refresh channel info',
              onPressed: _channelInfoLoading ? null : _refreshChannelInfo,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (_channelInfoLoading)
          const LinearProgressIndicator()
        else if (snapshot == null)
          Text('Unavailable: ${_channelInfoError ?? 'not configured'}')
        else ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              snapshot.isLive ? Icons.circle : Icons.circle_outlined,
              color: snapshot.isLive ? Colors.red : null,
            ),
            title: Text(
              snapshot.broadcasterName.isEmpty
                  ? snapshot.broadcasterId
                  : snapshot.broadcasterName,
            ),
            subtitle: Text(
              snapshot.isLive
                  ? '${snapshot.channelTitle.isEmpty ? 'Live' : snapshot.channelTitle} · ${snapshot.viewerCount ?? 0} viewers'
                  : 'Offline${snapshot.channelTitle.isEmpty ? '' : ' · ${snapshot.channelTitle}'}',
            ),
          ),
          if (snapshot.categoryName.isNotEmpty || snapshot.tags.isNotEmpty)
            Text(
              [
                if (snapshot.categoryName.isNotEmpty) snapshot.categoryName,
                if (snapshot.tags.isNotEmpty) snapshot.tags.join(', '),
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ],
    );
  }
}

List<String> _commaSeparated(String value) => value
    .split(',')
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toList();

final class _ChannelPointRewardDialog extends StatefulWidget {
  const _ChannelPointRewardDialog({this.reward});

  final TwitchChannelPointReward? reward;

  @override
  State<_ChannelPointRewardDialog> createState() =>
      _ChannelPointRewardDialogState();
}

final class _ChannelPointRewardDialogState
    extends State<_ChannelPointRewardDialog> {
  late final TextEditingController _title;
  late final TextEditingController _prompt;
  late final TextEditingController _color;
  late final TextEditingController _cost;
  late final TextEditingController _cooldown;
  late final TextEditingController _maxPerStream;
  late final TextEditingController _maxPerUser;
  late bool _enabled;
  late bool _userInputRequired;
  late bool _skipQueue;

  @override
  void initState() {
    super.initState();
    final reward = widget.reward;
    _title = TextEditingController(text: reward?.title ?? '');
    _prompt = TextEditingController(text: reward?.prompt ?? '');
    _color = TextEditingController(
      text: reward?.backgroundColor.isNotEmpty == true
          ? reward!.backgroundColor
          : '#9147ff',
    );
    _cost = TextEditingController(text: '${reward?.cost ?? 100}');
    _cooldown = TextEditingController(text: reward?.cooldown?.toString() ?? '');
    _maxPerStream = TextEditingController(
      text: reward?.maxRedemptionsPerStream?.toString() ?? '',
    );
    _maxPerUser = TextEditingController(
      text: reward?.maxRedemptionsPerUserPerStream?.toString() ?? '',
    );
    _enabled = reward?.isEnabled ?? true;
    _userInputRequired = reward?.userInputRequired ?? false;
    _skipQueue = reward?.skipQueue ?? false;
  }

  @override
  void dispose() {
    for (final controller in [
      _title,
      _prompt,
      _color,
      _cost,
      _cooldown,
      _maxPerStream,
      _maxPerUser,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.reward == null
          ? 'Create channel point reward'
          : 'Edit channel point reward',
    ),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _prompt,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Prompt'),
            ),
            TextField(
              controller: _color,
              decoration: const InputDecoration(
                labelText: 'Background color',
                hintText: '#9147ff',
              ),
            ),
            TextField(
              controller: _cost,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Cost'),
            ),
            TextField(
              controller: _cooldown,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Global cooldown (seconds)',
              ),
            ),
            TextField(
              controller: _maxPerStream,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Max redemptions per stream',
              ),
            ),
            TextField(
              controller: _maxPerUser,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Max redemptions per viewer per stream',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enabled'),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Require viewer input'),
              value: _userInputRequired,
              onChanged: (value) => setState(() => _userInputRequired = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Skip redemption queue'),
              value: _skipQueue,
              onChanged: (value) => setState(() => _skipQueue = value),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _title.text.trim().isEmpty ? null : _save,
        child: Text(widget.reward == null ? 'Create' : 'Save'),
      ),
    ],
  );

  void _save() {
    Navigator.pop(
      context,
      TwitchChannelPointRewardDraft(
        title: _title.text.trim(),
        prompt: _prompt.text,
        backgroundColor: _color.text.trim(),
        cost: (int.tryParse(_cost.text.trim()) ?? 1).clamp(1, 1000000),
        userInputRequired: _userInputRequired,
        skipQueue: _skipQueue,
        isEnabled: _enabled,
        maxRedemptionsPerStream: _optionalPositiveInt(_maxPerStream.text),
        maxRedemptionsPerUserPerStream: _optionalPositiveInt(_maxPerUser.text),
        cooldown: _optionalPositiveInt(_cooldown.text),
      ),
    );
  }

  int? _optionalPositiveInt(String value) {
    final parsed = int.tryParse(value.trim());
    return parsed == null || parsed < 1 ? null : parsed;
  }
}
