import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/brand_icons.dart';
import '../../plugins/registry/plugin_registry.dart';
import '../../plugins/runtime/provider_event_workers.dart';
import '../../plugins/twitch/channel_runtime.dart';
import '../../schema/resource.dart';
import '../../services/showrunner_data_service.dart';
import '../../plugins/twitch/account_runtime.dart';

import '../../design_system/workspace_notice.dart';
import 'dashboard_widgets.dart';

class TwitchDashboardCard extends StatefulWidget {
  const TwitchDashboardCard({
    super.key,
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
  State<TwitchDashboardCard> createState() => _TwitchDashboardCardState();
}

class _TwitchDashboardCardState extends State<TwitchDashboardCard> {
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
  void didUpdateWidget(covariant TwitchDashboardCard oldWidget) {
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
      await registry.invokeActionKey(
        const ActionKey(
          plugin: PluginId('twitch'),
          action: ActionId('setStreamInfo'),
        ),
        {
          'broadcasterId': settings['broadcasterId'],
          if (_titleController.text.trim().isNotEmpty)
            'title': _titleController.text.trim(),
          if (_categoryController.text.trim().isNotEmpty)
            'categoryId': _categoryId ?? _categoryController.text.trim(),
          if (_tags.isNotEmpty) 'tags': List<String>.from(_tags),
        },
      );
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
  Widget build(BuildContext context) => DashboardCard(
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
              WorkspaceNotice(
                message:
                    'Twitch sign-in failed. Check the account connection and retry.',
                icon: Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
              ),
            if (!channelConfigured)
              WorkspaceNotice(
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
              WorkspaceNotice(
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
          child: DashboardStatItem(
            label: 'Channel',
            value: widget.snapshot?.broadcasterName.isNotEmpty == true
                ? widget.snapshot!.broadcasterName
                : 'Configured',
          ),
        ),
        Expanded(
          child: DashboardStatItem(
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
          'Failed to update Twitch info. Check permissions and retry.',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (widget.error != null)
        Text(
          'Channel refresh failed: ${widget.error}',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ListenableBuilder(
        listenable: widget.providerEvents,
        builder: (context, _) => Text(
          widget.providerEvents.twitchState.label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );
}
