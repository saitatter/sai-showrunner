import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../plugins/runtime/provider_event_workers.dart';
import 'chat_message.dart';
import 'chat_completion.dart';
import 'chat_preferences_dialog.dart';
import 'chat_actions_dialog.dart';
import 'configured_chat_action.dart';
import 'unified_chat_runtime.dart';
import 'chat_dock_service.dart';

class ChatWorkspace extends StatefulWidget {
  const ChatWorkspace({
    super.key,
    required this.runtime,
    required this.providerEvents,
    this.dock,
  });
  final UnifiedChatRuntime runtime;
  final ProviderEventRuntime providerEvents;
  final ChatDockService? dock;
  @override
  State<ChatWorkspace> createState() => _ChatWorkspaceState();
}

class _ChatWorkspaceState extends State<ChatWorkspace> {
  final _message = TextEditingController();
  final _search = TextEditingController();
  ChatPlatform _destination = ChatPlatform.twitch;
  ChatPlatform? _filter;
  bool _busy = false;
  Object? _error;
  int _selectedSuggestion = 0;
  Set<String>? _pausedIdentities;
  String? _userIdentity;
  bool _showEvents = false;
  Set<String>? _pausedEventIds;
  List<ChatCompletion> get _suggestions {
    final selection = _message.selection;
    if (!selection.isValid || !selection.isCollapsed) return [];
    final before = _message.text.substring(0, selection.baseOffset);
    final word = before.split(RegExp(r'\s')).last;
    if (word.isEmpty || (word.length < 2 && word != '!' && word != '/')) {
      return [];
    }
    final firstWord = !before.trimLeft().contains(RegExp(r'\s'));
    return widget.runtime
        .composerCompletions(_destination)
        .where(
          (item) =>
              (item.kind == 'emote' || firstWord) &&
              (item.kind == 'emote' ? item.label : item.text)
                  .toLowerCase()
                  .startsWith(word.toLowerCase()),
        )
        .take(12)
        .toList();
  }

  void _insertSuggestion(ChatCompletion suggestion) {
    final cursor = _message.selection.baseOffset;
    if (cursor < 0) return;
    final prefix = _message.text.substring(0, cursor);
    final word = prefix.split(RegExp(r'\s')).last;
    final inserted = '${suggestion.text} ';
    setState(() {
      _message.value = TextEditingValue(
        text: _message.text.replaceRange(
          cursor - word.length,
          cursor,
          inserted,
        ),
        selection: TextSelection.collapsed(
          offset: cursor - word.length + inserted.length,
        ),
      );
      _selectedSuggestion = 0;
    });
  }

  void _completeOrSend() {
    final suggestions = _suggestions;
    if (suggestions.isNotEmpty) {
      _insertSuggestion(suggestions[_selectedSuggestion % suggestions.length]);
    } else {
      _send();
    }
  }

  void _stepSuggestion(int offset) {
    if (_suggestions.isNotEmpty) {
      setState(
        () => _selectedSuggestion =
            (_selectedSuggestion + offset) % _suggestions.length,
      );
    }
  }

  void _pause() => setState(() {
    _pausedIdentities = widget.runtime.messages.map((m) => m.identity).toSet();
    _pausedEventIds = widget.runtime.events.map((e) => e.id).toSet();
  });
  void _resume() => setState(() {
    _pausedIdentities = null;
    _pausedEventIds = null;
  });

  @override
  void dispose() {
    _message.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      _error = error;
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _send() => _run(() async {
    switch (_message.text.trim()) {
      case '/clear':
        widget.runtime.clearHistory();
      case '/pause':
        _pause();
      case '/resume':
        _resume();
      default:
        await widget.runtime.send(_destination, _message.text);
    }
    if (mounted) _message.clear();
  });
  Future<void> _moderate(ChatMessage message, ChatQuickAction action) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${action.name} on ${message.platform.name}?'),
        content: Text('${message.userName}: ${message.text}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (accepted == true) {
      await _run(() => widget.runtime.quickAction(message, action));
    }
  }

  Widget _eventFeed(UnifiedChatRuntime runtime, String search) {
    final events = runtime.events
        .where(
          (e) =>
              (_filter == null || e.platform == _filter) &&
              (_pausedEventIds == null || _pausedEventIds!.contains(e.id)) &&
              (_userIdentity == null ||
                  '${e.platform.name}:${e.userId}' == _userIdentity) &&
              (search.isEmpty ||
                  '${e.type} ${e.userName} ${e.message}'.toLowerCase().contains(
                    search,
                  )),
        )
        .toList();
    if (events.isEmpty) {
      return const Center(child: Text('No provider events in this session.'));
    }
    events.setAll(0, events.reversed.toList());
    return ListView.builder(
      reverse: !runtime.preferences.newestFirst,
      itemCount: events.length,
      itemBuilder: (context, index) {
        final event = events[index];
        final actions = runtime
            .actionsFor(ChatActionScope.event, event.platform)
            .toList();
        return ListTile(
          leading: const Icon(Icons.bolt),
          title: Text(
            '${runtime.preferences.timestamps ? '${event.time.toLocal().toIso8601String().substring(11, 19)} ' : ''}${event.platform.name} - ${event.type} - ${event.userName}',
          ),
          subtitle: Text(event.message),
          trailing: actions.isEmpty
              ? null
              : PopupMenuButton<String>(
                  tooltip: 'Event actions',
                  onSelected: _busy
                      ? null
                      : (id) => _run(
                          () => runtime.runConfiguredAction(
                            id,
                            platform: event.platform,
                            eventId: event.id,
                          ),
                        ),
                  itemBuilder: (_) => [
                    for (final action in actions)
                      PopupMenuItem(
                        value: action.id,
                        child: Text(action.label),
                      ),
                  ],
                ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.runtime,
      widget.runtime.commands,
      widget.providerEvents,
    ]),
    builder: (context, _) {
      final runtime = widget.runtime;
      final search = _search.text.toLowerCase();
      final preferences = runtime.preferences;
      final messages = runtime.messages
          .where(
            (m) =>
                (_filter == null || m.platform == _filter) &&
                (_userIdentity == null || m.userIdentity == _userIdentity) &&
                (_pausedIdentities == null ||
                    _pausedIdentities!.contains(m.identity)) &&
                (search.isEmpty ||
                    '${m.userName} ${m.text}'.toLowerCase().contains(search)),
          )
          .toList()
          .reversed
          .toList();
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Chat', style: Theme.of(context).textTheme.headlineSmall),
                Chip(
                  label: Text(
                    'Twitch: ${widget.providerEvents.twitchState.name}',
                  ),
                ),
                Chip(
                  label: Text(
                    'YouTube: ${widget.providerEvents.youtubeState.name}',
                  ),
                ),
                if (widget.providerEvents.botWhispers case final worker?)
                  Tooltip(
                    message:
                        worker.lastError?.toString() ?? 'Private command input',
                    child: Chip(
                      label: Text('Bot whispers: ${worker.state.name}'),
                    ),
                  ),
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => ChatActionsDialog(runtime: runtime),
                  ),
                  child: const Text('Chat actions'),
                ),
                IconButton(
                  tooltip: 'Chat preferences',
                  icon: const Icon(Icons.tune),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => ChatPreferencesDialog(runtime: runtime),
                  ),
                ),
                TextButton(
                  onPressed: runtime.clearHistory,
                  child: const Text('Clear local history'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(runtime.loadTwitchEmotes),
                  child: const Text('Load Twitch emotes'),
                ),
                TextButton.icon(
                  onPressed: () =>
                      _pausedIdentities == null ? _pause() : _resume(),
                  icon: Icon(
                    _pausedIdentities == null ? Icons.pause : Icons.play_arrow,
                  ),
                  label: Text(
                    _pausedIdentities == null ? 'Pause view' : 'Resume view',
                  ),
                ),
                if (_userIdentity != null)
                  InputChip(
                    label: Text('User: $_userIdentity'),
                    onDeleted: () => setState(() => _userIdentity = null),
                  ),
                if (widget.dock != null)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            final url = await widget.dock!.start();
                            await Clipboard.setData(
                              ClipboardData(text: url.toString()),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Dock URL copied. Add it in OBS → Docks → Custom Browser Docks.',
                                  ),
                                ),
                              );
                            }
                          }),
                    child: const Text('Copy OBS dock URL'),
                  ),
                if (widget.dock?.url != null)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() => widget.dock!.stop(disable: true)),
                    child: const Text('Stop OBS dock'),
                  ),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('All platforms'),
                  selected: _filter == null,
                  onSelected: (_) => setState(() => _filter = null),
                ),
                ChoiceChip(
                  label: const Text('Messages'),
                  selected: !_showEvents,
                  onSelected: (_) => setState(() => _showEvents = false),
                ),
                ChoiceChip(
                  label: const Text('Events'),
                  selected: _showEvents,
                  onSelected: (_) => setState(() => _showEvents = true),
                ),
                for (final platform in ChatPlatform.values)
                  ChoiceChip(
                    label: Text(platform.name),
                    selected: _filter == platform,
                    onSelected: (_) => setState(() => _filter = platform),
                  ),
              ],
            ),
            TextField(
              controller: _search,
              decoration: const InputDecoration(
                labelText: 'Search messages or users',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_error ?? runtime.error case final Object error)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  '$error',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (runtime
                .actionsFor(ChatActionScope.global, _destination)
                .isNotEmpty)
              Wrap(
                spacing: 8,
                children: [
                  for (final action in runtime.actionsFor(
                    ChatActionScope.global,
                    _destination,
                  ))
                    TextButton.icon(
                      icon: Icon(
                        chatActionIcon(action.icon),
                        color: chatActionColor(action.color),
                      ),
                      label: Text(action.label),
                      onPressed: _busy
                          ? null
                          : () => _run(
                              () => runtime.runConfiguredAction(
                                action.id,
                                platform: _destination,
                              ),
                            ),
                    ),
                ],
              ),
            Expanded(
              child: _showEvents
                  ? _eventFeed(runtime, search)
                  : messages.isEmpty
                  ? const Center(
                      child: Text(
                        'No messages. Connect Twitch or YouTube in Plugins.',
                      ),
                    )
                  : ListView.builder(
                      reverse: !preferences.newestFirst,
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        return ListTile(
                          tileColor: preferences.highlights(message)
                              ? Theme.of(context).colorScheme.primaryContainer
                              : preferences.alternatingRows && index.isOdd
                              ? Theme.of(context).colorScheme.surfaceContainer
                              : null,
                          leading: !preferences.platformIcons
                              ? null
                              : Tooltip(
                                  message: message.platform.name,
                                  child: Icon(
                                    message.platform == ChatPlatform.twitch
                                        ? Icons.live_tv
                                        : Icons.smart_display_outlined,
                                  ),
                                ),
                          title: Text(
                            '${preferences.timestamps ? '${message.receivedAt.toLocal().toIso8601String().substring(11, 19)} ' : ''}${message.userName}${preferences.roleBadges && message.isBroadcaster
                                ? ' · owner'
                                : preferences.roleBadges && message.isModerator
                                ? ' · moderator'
                                : ''}',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: preferences.highlights(message)
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.onPrimaryContainer
                                      : null,
                                ),
                          ),
                          subtitle: SelectableText(
                            message.deleted ? 'Message deleted' : message.text,
                            style: TextStyle(
                              fontSize: preferences.fontSize,
                              color: preferences.highlights(message)
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.onPrimaryContainer
                                  : null,
                              fontFamily: preferences.font == 'system'
                                  ? null
                                  : preferences.font,
                            ),
                          ),
                          trailing: PopupMenuButton<String>(
                            tooltip: 'Message and user actions',
                            onSelected: (value) {
                              if (value == 'copy') {
                                Clipboard.setData(
                                  ClipboardData(text: message.text),
                                );
                              } else if (value == 'reply') {
                                setState(() {
                                  _destination = message.platform;
                                  _message.text = '@${message.userName} ';
                                });
                              } else if (value == 'user') {
                                setState(
                                  () => _userIdentity = message.userIdentity,
                                );
                              } else if (value.startsWith('configured:')) {
                                _run(
                                  () => runtime.runConfiguredAction(
                                    value.substring('configured:'.length),
                                    platform: message.platform,
                                    messageIdentity: message.identity,
                                  ),
                                );
                              } else {
                                _moderate(
                                  message,
                                  ChatQuickAction.values.byName(value),
                                );
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'reply',
                                child: Text('Reply'),
                              ),
                              const PopupMenuItem(
                                value: 'copy',
                                child: Text('Copy message'),
                              ),
                              const PopupMenuItem(
                                value: 'user',
                                child: Text('Show messages from user'),
                              ),
                              if (!_busy && !message.deleted)
                                for (final scope in [
                                  ChatActionScope.message,
                                  ChatActionScope.user,
                                ])
                                  for (final action in runtime.actionsFor(
                                    scope,
                                    message.platform,
                                  ))
                                    PopupMenuItem(
                                      value: 'configured:${action.id}',
                                      child: Row(
                                        children: [
                                          Icon(
                                            chatActionIcon(action.icon),
                                            color: chatActionColor(
                                              action.color,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${scope.name}: ${action.label}',
                                          ),
                                        ],
                                      ),
                                    ),
                              if (!_busy &&
                                  !message.deleted &&
                                  message.id.isNotEmpty)
                                const PopupMenuItem(
                                  value: 'deleteMessage',
                                  child: Text('Delete message'),
                                ),
                              if (!_busy &&
                                  !message.isBroadcaster &&
                                  message.userId.isNotEmpty) ...[
                                const PopupMenuItem(
                                  value: 'timeout',
                                  child: Text('Timeout for 60 seconds'),
                                ),
                                const PopupMenuItem(
                                  value: 'ban',
                                  child: Text('Ban user'),
                                ),
                                if (message.platform == ChatPlatform.twitch)
                                  const PopupMenuItem(
                                    value: 'unban',
                                    child: Text('Unban user'),
                                  ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
            if (_suggestions.isNotEmpty)
              Wrap(
                spacing: 6,
                children: [
                  for (final (index, suggestion) in _suggestions.indexed)
                    InputChip(
                      selected:
                          index == _selectedSuggestion % _suggestions.length,
                      label: Text(suggestion.label),
                      onPressed: () => _insertSuggestion(suggestion),
                    ),
                ],
              ),
            Row(
              children: [
                DropdownButton<ChatPlatform>(
                  value: _destination,
                  onChanged: _busy
                      ? null
                      : (v) {
                          if (v != null) setState(() => _destination = v);
                        },
                  items: ChatPlatform.values
                      .map(
                        (p) => DropdownMenuItem(value: p, child: Text(p.name)),
                      )
                      .toList(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.tab): () {
                        final suggestions = _suggestions;
                        if (suggestions.isNotEmpty) {
                          _insertSuggestion(
                            suggestions[_selectedSuggestion %
                                suggestions.length],
                          );
                        }
                      },
                      const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                          _stepSuggestion(1),
                      const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                          _stepSuggestion(-1),
                    },
                    child: TextField(
                      controller: _message,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Message',
                        hintText: 'Send to the selected platform',
                      ),
                      onSubmitted: (_) => _completeOrSend(),
                      onChanged: (_) => setState(() => _selectedSuggestion = 0),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  tooltip: 'Send message',
                  onPressed: _busy ? null : _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
