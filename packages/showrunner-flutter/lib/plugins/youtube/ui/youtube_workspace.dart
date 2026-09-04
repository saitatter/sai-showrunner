import 'dart:async';

import 'package:flutter/material.dart';

import '../../../runtime/expression.dart';
import '../../../services/showrunner_data_service.dart';
import '../../registry/plugin_registry.dart';
import '../../runtime/provider_event_workers.dart';

class YouTubeWorkspace extends StatefulWidget {
  const YouTubeWorkspace({
    super.key,
    required this.dataService,
    required this.providerEvents,
    required this.registryFuture,
  });

  final ShowRunnerDataService dataService;
  final ProviderEventRuntime providerEvents;
  final Future<DartPluginRegistry> registryFuture;

  @override
  State<YouTubeWorkspace> createState() => _YouTubeWorkspaceState();
}

class _YouTubeWorkspaceState extends State<YouTubeWorkspace> {
  late final TextEditingController _liveChatIdController;
  late final TextEditingController _chatMessageController;
  late final TextEditingController _messageIdController;
  late final TextEditingController _channelIdController;
  bool _loading = true;
  bool _busy = false;
  Object? _error;
  Map<String, dynamic> _settings = const {};
  StreamSubscription<RuntimeMap>? _messageSubscription;
  String? _latestAuthor;
  String? _latestMessage;
  final _messageHistory = <String>[];

  @override
  void initState() {
    super.initState();
    _liveChatIdController = TextEditingController();
    _chatMessageController = TextEditingController();
    _messageIdController = TextEditingController();
    _channelIdController = TextEditingController();
    _messageSubscription = widget.providerEvents.eventHub
        .stream('chatMessage')
        .listen((message) {
          final snippet = message['snippet'] as Map?;
          final author = message['authorDetails'] as Map?;
          if (!mounted) return;
          setState(() {
            _latestAuthor = author?['displayName']?.toString();
            _latestMessage = snippet?['displayMessage']?.toString();
            _messageHistory.insert(
              0,
              '${_latestAuthor ?? 'Unknown'}: ${_latestMessage ?? 'Empty message'}',
            );
            if (_messageHistory.length > 20) _messageHistory.removeLast();
          });
        });
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await widget.dataService.loadPluginSettings('youtube');
      _settings = settings;
      _liveChatIdController.text = settings['liveChatId']?.toString() ?? '';
    } catch (error) {
      _error = error;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveAndStart() async {
    final liveChatId = _liveChatIdController.text.trim();
    if (liveChatId.isEmpty) {
      setState(() => _error = ArgumentError('Live Chat ID is required.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final settings = await widget.dataService.loadPluginSettings('youtube');
      await widget.dataService.savePluginSettings('youtube', {
        ...settings,
        'liveChatId': liveChatId,
      });
      await widget.providerEvents.startYouTubeChat(liveChatId: liveChatId);
    } catch (error) {
      _error = error;
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _stop() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.providerEvents.stopYouTubeChat();
    } catch (error) {
      _error = error;
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _discover() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final broadcast = await widget.providerEvents.discoverYouTubeBroadcast();
      final liveChatId = broadcast['liveChatId']?.toString();
      if (liveChatId != null && liveChatId.isNotEmpty) {
        _liveChatIdController.text = liveChatId;
      }
    } catch (error) {
      _error = error;
    }
    if (mounted) setState(() => _busy = false);
  }

  void _simulate() {
    widget.providerEvents.simulateYouTubeChatMessage();
  }

  Future<void> _invoke(String actionId, RuntimeMap config) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final registry = await widget.registryFuture;
      await registry.invokeAction('youtube', actionId, config);
    } catch (error) {
      _error = error;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  void dispose() {
    unawaited(_messageSubscription?.cancel());
    _liveChatIdController.dispose();
    _chatMessageController.dispose();
    _messageIdController.dispose();
    _channelIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return AnimatedBuilder(
      animation: widget.providerEvents,
      builder: (context, _) {
        final running = widget.providerEvents.youtubeChatRunning;
        final runtimeError = widget.providerEvents.youtubeLastError;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'YouTube Live',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('Dart-owned live chat ingest control.'),
            const SizedBox(height: 24),
            TextField(
              controller: _liveChatIdController,
              decoration: const InputDecoration(
                labelText: 'Live Chat ID',
                border: OutlineInputBorder(),
              ),
              enabled: !_busy && !running,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _busy || running ? null : _saveAndStart,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start chat'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _busy || !running ? null : _stop,
                  icon: const Icon(Icons.stop),
                  label: const Text('Stop chat'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _discover,
                  icon: const Icon(Icons.search),
                  label: const Text('Discover live'),
                ),
                const SizedBox(width: 12),
                IconButton(
                  tooltip: 'Simulate chat message',
                  onPressed: _busy ? null : _simulate,
                  icon: const Icon(Icons.forum_outlined),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Card(
              child: ListTile(
                leading: Icon(
                  running ? Icons.check_circle : Icons.pause_circle,
                  color: running ? Colors.green : null,
                ),
                title: const Text('Ingest status'),
                subtitle: Text(running ? 'Running' : 'Stopped'),
              ),
            ),
            _YouTubeOAuthStatus(settings: _settings),
            if (widget.providerEvents.youtubeBroadcast != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.live_tv),
                  title: Text(
                    widget.providerEvents.youtubeBroadcast!['title']
                            ?.toString() ??
                        'YouTube broadcast',
                  ),
                  subtitle: Text(
                    'Status: ${widget.providerEvents.youtubeBroadcast!['status'] ?? 'unknown'}',
                  ),
                ),
              ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.chat_bubble_outline),
                title: Text(_latestMessage ?? 'No chat messages yet'),
                subtitle: Text(_latestAuthor ?? 'Latest YouTube message'),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Chat controls',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _chatMessageController,
                      decoration: const InputDecoration(labelText: 'Message'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed:
                          _busy || _chatMessageController.text.trim().isEmpty
                          ? null
                          : () => _invoke('sendChatMessage', {
                              'liveChatId': _liveChatIdController.text.trim(),
                              'message': _chatMessageController.text.trim(),
                            }),
                      icon: const Icon(Icons.send),
                      label: const Text('Send message'),
                    ),
                    const Divider(height: 24),
                    TextField(
                      controller: _messageIdController,
                      decoration: const InputDecoration(
                        labelText: 'Message ID',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    TextField(
                      controller: _channelIdController,
                      decoration: const InputDecoration(
                        labelText: 'Channel ID',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed:
                              _busy || _messageIdController.text.trim().isEmpty
                              ? null
                              : () => _invoke('deleteMessage', {
                                  'messageId': _messageIdController.text.trim(),
                                }),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete'),
                        ),
                        OutlinedButton.icon(
                          onPressed:
                              _busy || _channelIdController.text.trim().isEmpty
                              ? null
                              : () => _invoke('banUser', {
                                  'liveChatId': _liveChatIdController.text
                                      .trim(),
                                  'channelId': _channelIdController.text.trim(),
                                }),
                          icon: const Icon(Icons.block),
                          label: const Text('Ban'),
                        ),
                      ],
                    ),
                  ],
                ),
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
            if (_error != null || runtimeError != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: const Text('YouTube ingest error'),
                  subtitle: Text('${_error ?? runtimeError}'),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _YouTubeOAuthStatus extends StatelessWidget {
  const _YouTubeOAuthStatus({required this.settings});

  final Map<String, dynamic> settings;

  @override
  Widget build(BuildContext context) {
    final accessToken = settings['accessToken']?.toString() ?? '';
    final refreshToken = settings['refreshToken']?.toString() ?? '';
    final expiresAt = DateTime.tryParse(
      settings['expiresAt']?.toString() ?? '',
    );
    final expired = expiresAt != null && DateTime.now().isAfter(expiresAt);
    final label = accessToken.isEmpty
        ? 'Not authorized'
        : expired
        ? 'Access token expired'
        : 'Access token available';
    final detail = refreshToken.isEmpty
        ? 'Refresh token missing'
        : 'Refresh token available';
    return Card(
      child: ListTile(
        leading: Icon(
          accessToken.isEmpty || expired ? Icons.warning_amber : Icons.verified,
          color: accessToken.isEmpty || expired ? Colors.amber : Colors.green,
        ),
        title: const Text('YouTube OAuth status'),
        subtitle: Text(
          '$label. $detail${expiresAt == null ? '' : '\nExpires: $expiresAt'}',
        ),
      ),
    );
  }
}
