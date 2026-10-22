import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../plugins/runtime/provider_event_workers.dart';
import 'chat_message.dart';
import 'chat_completion.dart';
import 'chat_preferences_dialog.dart';
import 'chat_actions_dialog.dart';
import 'configured_chat_action.dart';
import 'chat_timeline.dart';
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
  final _composerFocus = FocusNode();
  final _search = TextEditingController();
  ChatPlatform _destination = ChatPlatform.twitch;
  ChatPlatform? _filter;
  bool _busy = false;
  Object _owner = Object();
  bool _isCurrent(Object owner) => mounted && identical(owner, _owner);
  @override
  void didUpdateWidget(covariant ChatWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.runtime != widget.runtime ||
        oldWidget.providerEvents != widget.providerEvents ||
        oldWidget.dock != widget.dock) {
      _owner = Object();
      _busy = false;
      _error = null;
      _pausedIdentities = null;
      _pausedEventIds = null;
      _userIdentity = null;
    }
  }

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
    _composerFocus.requestFocus();
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
    _composerFocus.dispose();
    _message.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || !mounted) return;
    final owner = _owner;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (_isCurrent(owner)) _error = error;
    }
    if (_isCurrent(owner)) setState(() => _busy = false);
  }

  Future<void> _send() {
    final owner = _owner;
    final runtime = widget.runtime;
    final text = _message.text;
    final destination = _destination;
    return _run(() async {
      switch (text.trim()) {
        case '/clear':
          runtime.clearHistory();
        case '/pause':
          _pause();
        case '/resume':
          _resume();
        default:
          await runtime.send(destination, text);
      }
      if (_isCurrent(owner) && _message.text == text) _message.clear();
    });
  }

  Future<void> _moderate(ChatMessage message, ChatQuickAction action) async {
    final owner = _owner;
    final runtime = widget.runtime;
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
    if (accepted == true && _isCurrent(owner)) {
      await _run(() => runtime.quickAction(message, action));
    }
  }

  @override
  Widget build(BuildContext context) {
    final runtime = widget.runtime;
    final search = _search.text.toLowerCase();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListenableBuilder(
            listenable: Listenable.merge([runtime, widget.providerEvents]),
            builder: (context, _) => Wrap(
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
                    message: worker.lastError == null
                        ? 'Private command input'
                        : 'Private command input unavailable. Check authentication.',
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
                      : () => _run(() => runtime.loadEmotes(_destination)),
                  child: Text('Load ${_destination.name} emotes'),
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
                if (runtime.emoteCatalog.status.isNotEmpty)
                  Tooltip(
                    message: runtime.emoteCatalog.status.entries
                        .map((e) => '${e.key}: ${e.value}')
                        .join('\n'),
                    child: Chip(
                      label: Text(
                        runtime.emoteCatalog.status.values.any(
                              (s) => s == 'unavailable',
                            )
                            ? 'Emotes: some catalogs unavailable'
                            : 'Emote catalogs loaded',
                      ),
                    ),
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
          ListenableBuilder(
            listenable: runtime,
            builder: (context, _) => _error != null || runtime.error != null
                ? const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Chat operation failed. Check the connection and retry.',
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          ListenableBuilder(
            listenable: runtime,
            builder: (context, _) =>
                runtime
                    .actionsFor(ChatActionScope.global, _destination)
                    .isNotEmpty
                ? Wrap(
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
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(
            child: ChatTimeline(
              runtime: runtime,
              search: search,
              filter: _filter,
              userIdentity: _userIdentity,
              pausedIdentities: _pausedIdentities,
              pausedEventIds: _pausedEventIds,
              showEvents: _showEvents,
              busy: _busy,
              onRun: _run,
              onModerate: _moderate,
              onReply: (message) {
                setState(() {
                  _destination = message.platform;
                  _message.text = '@${message.userName} ';
                });
                _composerFocus.requestFocus();
              },
              onUser: (identity) => setState(() => _userIdentity = identity),
            ),
          ),
          ListenableBuilder(
            listenable: Listenable.merge([runtime, runtime.commands]),
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_suggestions.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final (index, suggestion) in _suggestions.indexed)
                        InputChip(
                          selected:
                              index ==
                              _selectedSuggestion % _suggestions.length,
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
                            (p) =>
                                DropdownMenuItem(value: p, child: Text(p.name)),
                          )
                          .toList(),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CallbackShortcuts(
                        bindings: {
                          if (_suggestions.isNotEmpty) ...{
                            const SingleActivator(LogicalKeyboardKey.tab): () {
                              final suggestions = _suggestions;
                              if (suggestions.isNotEmpty) {
                                _insertSuggestion(
                                  suggestions[_selectedSuggestion %
                                      suggestions.length],
                                );
                              }
                            },
                            const SingleActivator(
                              LogicalKeyboardKey.arrowDown,
                            ): () =>
                                _stepSuggestion(1),
                            const SingleActivator(
                              LogicalKeyboardKey.arrowUp,
                            ): () =>
                                _stepSuggestion(-1),
                          },
                        },
                        child: TextField(
                          controller: _message,
                          focusNode: _composerFocus,
                          enabled: !_busy,
                          decoration: const InputDecoration(
                            labelText: 'Message',
                            hintText: 'Send to the selected platform',
                          ),
                          onSubmitted: (_) => _completeOrSend(),
                          onChanged: (_) =>
                              setState(() => _selectedSuggestion = 0),
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
          ),
        ],
      ),
    );
  }
}
