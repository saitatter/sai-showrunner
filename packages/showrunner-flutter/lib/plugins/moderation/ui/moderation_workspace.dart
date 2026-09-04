import 'dart:async';

import 'package:flutter/material.dart';

import '../runtime.dart';

class ModerationWorkspace extends StatefulWidget {
  const ModerationWorkspace({super.key, required this.service});

  final ModerationService service;

  @override
  State<ModerationWorkspace> createState() => _ModerationWorkspaceState();
}

class _ModerationWorkspaceState extends State<ModerationWorkspace> {
  late final ModerationService _service;
  late final TextEditingController _urlController;
  late final TextEditingController _tokenController;
  late final TextEditingController _socketController;
  late final StreamSubscription<ModerationStatus> _statusSubscription;
  bool _enabled = false;
  bool _forwardYouTube = true;
  bool _loading = true;
  bool _busy = false;
  Object? _error;
  final _queueFilters = <String, String>{
    'text': '',
    'platform': '',
    'verdict': '',
  };
  final _queueVisibleCount = <String, int>{
    'latest': 50,
    'pending': 50,
    'approved': 50,
    'rejected': 50,
  };
  final _activityLog = <_ModerationActivity>[];
  Map<String, List<Map<String, dynamic>>> _queues = const {
    'latest': [],
    'pending': [],
    'approved': [],
    'rejected': [],
  };

  @override
  void initState() {
    super.initState();
    _service = widget.service;
    _urlController = TextEditingController();
    _tokenController = TextEditingController();
    _socketController = TextEditingController();
    _statusSubscription = _service.statusChanges.listen((status) {
      if (mounted) setState(() {});
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await _service.loadSettings();
      _enabled = settings.enabled;
      _forwardYouTube = settings.forwardYouTube;
      _urlController.text = settings.apiBaseUrl;
      _tokenController.text = settings.apiToken;
      _socketController.text = settings.dashboardWsUrl;
    } catch (error) {
      _error = error;
    }
    if (mounted) setState(() => _loading = false);
  }

  ModerationSettings _settings() => ModerationSettings(
    enabled: _enabled,
    apiBaseUrl: _urlController.text.trim(),
    apiToken: _tokenController.text,
    dashboardWsUrl: _socketController.text.trim(),
    forwardYouTube: _forwardYouTube,
  );

  Future<void> _save() async {
    await _run(() async {
      await _service.saveSettings(_settings());
      await _service.checkHealth();
      await _service.connectDashboard();
    }, summary: 'Moderation settings saved.');
  }

  Future<void> _health() async {
    await _run(() async {
      await _service.checkHealth();
    }, summary: 'Moderation health check finished.');
  }

  Future<void> _test() async {
    await _run(() async {
      await _service.sendTestMessage();
    }, summary: 'Moderation test event sent.');
  }

  Future<void> _refreshQueue() async {
    await _run(() async {
      final response = await _service.getQueue();
      _setQueues(response);
    }, summary: 'Moderation queue refreshed.');
  }

  Future<void> _override(String messageId, String action) async {
    await _run(() async {
      final response = await _service.requestOverride(
        messageId: messageId,
        action: action,
      );
      _setQueues(response);
    }, summary: 'Manual moderation override: $action · $messageId');
  }

  void _setQueues(Map<String, dynamic> response) {
    _queues = {
      for (final key in ['latest', 'pending', 'approved', 'rejected'])
        key: response[key] is List
            ? (response[key] as List)
                  .whereType<Map>()
                  .map(Map<String, dynamic>.from)
                  .toList()
            : const [],
    };
  }

  List<Map<String, dynamic>> _filteredQueue(String key) {
    final text = _queueFilters['text']!.trim().toLowerCase();
    final platform = _queueFilters['platform']!.trim().toLowerCase();
    final verdict = _queueFilters['verdict']!.trim().toLowerCase();
    return (_queues[key] ?? []).where((entry) {
      final haystack = [
        entry['text'],
        entry['username'],
        entry['messageId'],
        entry['category'],
        entry['reason'],
      ].whereType<Object>().join(' ').toLowerCase();
      return (text.isEmpty || haystack.contains(text)) &&
          (platform.isEmpty ||
              entry['platform']?.toString().toLowerCase() == platform) &&
          (verdict.isEmpty ||
              entry['verdict']?.toString().toLowerCase() == verdict);
    }).toList();
  }

  Future<void> _run(Future<void> Function() action, {String? summary}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (summary != null) _addActivity('info', summary);
    } catch (error) {
      _error = error;
      _addActivity('error', 'Moderation action failed.', '$error');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    _socketController.dispose();
    _statusSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final status = _service.status;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Moderation Docker',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text('Moderation health, queue, and operator controls.'),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Connection',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: _busy ? null : () => _applyPreset('local'),
                      child: const Text('Localhost'),
                    ),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _applyPreset('dockerHost'),
                      child: const Text('Docker Host'),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable moderation docker'),
                  value: _enabled,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _enabled = value),
                ),
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(labelText: 'API URL'),
                ),
                TextField(
                  controller: _tokenController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'API token'),
                ),
                TextField(
                  controller: _socketController,
                  decoration: const InputDecoration(
                    labelText: 'Dashboard WebSocket URL',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Forward YouTube chat'),
                  value: _forwardYouTube,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _forwardYouTube = value),
                ),
                Wrap(
                  spacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: const Icon(Icons.save),
                      label: const Text('Save'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _health,
                      icon: const Icon(Icons.health_and_safety),
                      label: const Text('Health'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _test,
                      icon: const Icon(Icons.send),
                      label: const Text('Send test'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            _counter('Processed', status.processedMessages),
            _counter('Approved', status.approvedMessages),
            _counter('Blocked', status.blockedMessages),
            _counter('Flagged', status.flaggedMessages),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _filterField('text', 'Search messages'),
                _filterDropdown('platform', 'Platform', const {
                  '': 'All',
                  'twitch': 'Twitch',
                  'youtube': 'YouTube',
                }),
                _filterDropdown('verdict', 'Verdict', const {
                  '': 'All',
                  'allow': 'Allow',
                  'flag': 'Flag',
                  'block': 'Block',
                  'approved': 'Approved',
                  'rejected': 'Rejected',
                }),
              ],
            ),
          ),
        ),
        Card(
          child: ListTile(
            leading: Icon(
              status.health == 'healthy'
                  ? Icons.check_circle
                  : Icons.info_outline,
            ),
            title: Text('Health: ${status.health}'),
            subtitle: Text(
              '${status.statusMessage}\nWebSocket: ${status.connected ? 'connected' : 'disconnected'}',
            ),
            trailing: IconButton(
              tooltip: 'Refresh queue',
              onPressed: _busy ? null : _refreshQueue,
              icon: const Icon(Icons.refresh),
            ),
          ),
        ),
        if (_error != null)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              title: const Text('Moderation error'),
              subtitle: Text('$_error'),
            ),
          ),
        if (status.recentDecisions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Latest decisions',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          ...status.recentDecisions.map(
            (decision) => ListTile(
              dense: true,
              leading: Icon(_decisionIcon(decision.decision)),
              title: Text(decision.decision),
              subtitle: Text(
                '${decision.eventType} · ${decision.messageId ?? decision.receivedAt}',
              ),
            ),
          ),
        ],
        for (final bucket in ['pending', 'approved', 'rejected', 'latest'])
          _queueSection(context, bucket),
        if (_activityLog.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Activity Log', style: Theme.of(context).textTheme.titleLarge),
          ..._activityLog.map(
            (entry) => ListTile(
              dense: true,
              leading: Icon(
                entry.severity == 'error' ? Icons.error : Icons.info_outline,
              ),
              title: Text(entry.summary),
              subtitle: Text(entry.detail),
            ),
          ),
        ],
      ],
    );
  }

  void _applyPreset(String preset) {
    final values = preset == 'dockerHost'
        ? const {
            'api': 'http://host.docker.internal:8787',
            'ws': 'ws://host.docker.internal:8787/ws?channel=dashboard',
          }
        : const {
            'api': 'http://localhost:8787',
            'ws': 'ws://localhost:8787/ws?channel=dashboard',
          };
    setState(() {
      _urlController.text = values['api']!;
      _socketController.text = values['ws']!;
    });
  }

  Widget _queueSection(BuildContext context, String bucket) {
    final entries = _filteredQueue(bucket);
    final visible = entries.take(_queueVisibleCount[bucket] ?? 50).toList();
    final label = '${bucket[0].toUpperCase()}${bucket.substring(1)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(
          '$label (${entries.length})',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (entries.isEmpty)
          const ListTile(title: Text('No matching messages.'))
        else
          ...visible.map(
            (entry) => Card(
              child: ListTile(
                title: Text(entry['text']?.toString() ?? 'Unknown message'),
                subtitle: Text(
                  '${entry['username'] ?? 'unknown'} · ${entry['platform'] ?? 'unknown'}\n'
                  '${entry['messageId'] ?? ''} · ${entry['verdict'] ?? ''}',
                ),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  enabled: !_busy,
                  onSelected: (action) =>
                      _override(entry['messageId']?.toString() ?? '', action),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'approve', child: Text('Approve')),
                    PopupMenuItem(value: 'block', child: Text('Block')),
                    PopupMenuItem(
                      value: 'falsePositive',
                      child: Text('False positive'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (entries.length > visible.length)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(
                () => _queueVisibleCount[bucket] = visible.length + 50,
              ),
              child: Text(
                'Show more (${entries.length - visible.length} remaining)',
              ),
            ),
          ),
      ],
    );
  }

  Widget _counter(String label, int value) => Chip(
    avatar: CircleAvatar(child: Text('$value')),
    label: Text(label),
  );

  Widget _filterField(String key, String label) => SizedBox(
    width: 190,
    child: TextField(
      decoration: InputDecoration(labelText: label, isDense: true),
      onChanged: (value) => setState(() => _queueFilters[key] = value),
    ),
  );

  Widget _filterDropdown(
    String key,
    String label,
    Map<String, String> options,
  ) => SizedBox(
    width: 190,
    child: DropdownButtonFormField<String>(
      initialValue: _queueFilters[key],
      decoration: InputDecoration(labelText: label, isDense: true),
      items: options.entries
          .map(
            (entry) =>
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          )
          .toList(),
      onChanged: (value) => setState(() => _queueFilters[key] = value ?? ''),
    ),
  );

  void _addActivity(String severity, String summary, [String detail = '']) {
    _activityLog.insert(0, _ModerationActivity(severity, summary, detail));
    if (_activityLog.length > 12) _activityLog.removeLast();
  }

  IconData _decisionIcon(String decision) => switch (decision) {
    'allow' || 'approved' => Icons.check_circle,
    'block' || 'blocked' || 'rejected' => Icons.block,
    'flag' || 'flagged' || 'pending' => Icons.flag,
    _ => Icons.info_outline,
  };
}

final class _ModerationActivity {
  const _ModerationActivity(this.severity, this.summary, this.detail);

  final String severity;
  final String summary;
  final String detail;
}
