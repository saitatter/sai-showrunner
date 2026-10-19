import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../plugins/registry/plugin_registry.dart';
import '../../plugins/twitch/account_runtime.dart';
import '../../services/plugin_event_hub.dart';
import '../../services/showrunner_data_service.dart';
import '../../services/http_provider_transports.dart';
import 'chat_message.dart';
import 'chat_completion.dart';
import 'chat_preferences.dart';
import 'configured_chat_action.dart';
import 'chat_emote.dart';
import 'chat_emote_catalog.dart';
import 'command_manager.dart';

enum ChatQuickAction { deleteMessage, timeout, ban, unban }

final class UnifiedChatRuntime extends ChangeNotifier {
  UnifiedChatRuntime({
    required this.eventHub,
    required this.dataService,
    required this.registryFuture,
    required this.commands,
    this.youtubeLiveChatId,
    this.executeAction,
    ChatEmoteCatalog? emoteCatalog,
    this.historyLimit = 500,
  }) : emoteCatalog = emoteCatalog ?? ChatEmoteCatalog();

  final ChatEmoteCatalog emoteCatalog;
  final DartPluginEventHub eventHub;
  final ShowRunnerDataService dataService;
  final Future<DartPluginRegistry> registryFuture;
  final ChatCommandManager commands;
  final String? Function()? youtubeLiveChatId;
  final int historyLimit;
  final Future<void> Function(ConfiguredChatAction, Map<String, dynamic>)?
  executeAction;
  List<ConfiguredChatAction> _configuredActions = [];
  List<ConfiguredChatAction> get configuredActions =>
      List.unmodifiable(_configuredActions);
  bool _actionsValid = true;
  final _events = <ChatFeedEvent>[];
  final _seenEvents = <String>{};
  int _eventSequence = 0;
  List<ChatFeedEvent> get events => List.unmodifiable(_events);

  Future<void> saveActions(List<ConfiguredChatAction> actions) async {
    if (!_actionsValid) {
      throw StateError('Existing chat actions are invalid and were preserved.');
    }
    if (actions.length > 100 ||
        actions.map((a) => a.id).toSet().length != actions.length) {
      throw const FormatException('Too many chat actions or duplicate IDs.');
    }
    final snapshot = List<ConfiguredChatAction>.of(actions);
    await dataService.savePluginSettings('chat-actions', {
      'version': 1,
      'actions': snapshot.map((a) => a.toJson()).toList(),
    });
    _configuredActions = snapshot;
    if (!_closed) notifyListeners();
  }

  Iterable<ConfiguredChatAction> actionsFor(
    ChatActionScope scope,
    ChatPlatform platform,
  ) => _configuredActions.where(
    (a) => a.enabled && a.scope == scope && a.platforms.contains(platform),
  );

  Future<void> runConfiguredAction(
    String id, {
    required ChatPlatform platform,
    String? messageIdentity,
    String? eventId,
    String input = '',
  }) async {
    final action = _configuredActions
        .where((a) => a.id == id && a.enabled)
        .firstOrNull;
    if (action == null || !action.platforms.contains(platform)) {
      throw StateError('Chat action is unavailable.');
    }
    Map<String, dynamic> target = {'platform': platform.name};
    switch (action.scope) {
      case ChatActionScope.global:
        break;
      case ChatActionScope.message || ChatActionScope.user:
        final message = messages
            .where(
              (m) =>
                  m.identity == messageIdentity &&
                  m.platform == platform &&
                  !m.deleted,
            )
            .firstOrNull;
        if (message == null) {
          throw StateError('The target message is no longer available.');
        }
        target = message.context;
      case ChatActionScope.event:
        final event = _events
            .where((e) => e.id == eventId && e.platform == platform)
            .firstOrNull;
        if (event == null) {
          throw StateError('The target event is no longer available.');
        }
        target = event.context;
    }
    final execute = executeAction;
    if (execute == null) {
      throw StateError('Chat action execution is unavailable.');
    }
    await execute(action, {
      ...target,
      'chatActionId': id,
      'chatActionScope': action.scope.name,
      'actionArguments': action.arguments,
      'actionInput': input,
    });
  }

  void _addFeedEvent(
    ChatPlatform platform,
    String type,
    Map<String, dynamic> values,
  ) {
    String value(Object? text) =>
        text is String ? text.substring(0, text.length.clamp(0, 2000)) : '';
    final snippet = values['snippet'] is Map
        ? values['snippet'] as Map
        : const {};
    final author = values['authorDetails'] is Map
        ? values['authorDetails'] as Map
        : const {};
    final providerId = value(values['id']);
    final id =
        '${platform.name}:$type:${providerId.isEmpty ? ++_eventSequence : providerId}';
    if (!_seenEvents.add(id)) return;
    if (_seenEvents.length > 4096) _seenEvents.remove(_seenEvents.first);
    _events.add(
      ChatFeedEvent(
        id: id,
        platform: platform,
        type: type,
        time: DateTime.now(),
        userId: value(
          values['viewerId'] ?? values['user_id'] ?? author['channelId'],
        ),
        userName: value(
          values['viewerName'] ?? values['user_name'] ?? author['displayName'],
        ),
        message: value(
          values['message'] ??
              values['user_input'] ??
              snippet['displayMessage'],
        ),
      ),
    );
    while (_events.length > historyLimit) {
      _events.removeAt(0);
    }
    if (!_closed) notifyListeners();
  }

  final _subscriptions = <StreamSubscription<Map<String, dynamic>>>[];
  final _messages = <ChatMessage>[];
  final _seen = <String>{};
  final _deletedIds = <String>{};
  final _clearBefore = <String, DateTime>{};
  final _botIds = <ChatPlatform, Set<String>>{};
  String _liveChatId = '';
  String _twitchChannelId = '';
  bool _closed = false;
  Object? error;
  ChatPreferences preferences = ChatPreferences();
  bool _preferencesValid = true;
  int _changingPreferences = 0;
  final _hidden = <String>{};
  final _pending = <String>{};
  Future<void> _filterTail = Future.value();
  Future<void> get filtersSettled => _filterTail;
  final List<ChatEmote> emotes = [
    const ChatEmote(':smile:', '😀'),
    const ChatEmote(':heart:', '❤️'),
    const ChatEmote(':wave:', '👋'),
    const ChatEmote(':party:', '🎉'),
  ];
  List<ChatMessage> get messages => List.unmodifiable(
    _messages.where(
      (message) =>
          !_hidden.contains(message.identity) &&
          !_pending.contains(message.identity),
    ),
  );

  Future<void> savePreferences(ChatPreferences next) async {
    if (!_preferencesValid) {
      throw StateError(
        'Existing chat preferences are invalid and were preserved.',
      );
    }
    if (_closed) throw StateError('Chat runtime is closed.');
    _changingPreferences++;
    final saved = _filterTail
        .then((_) async {
          final hidden = <String>{};
          for (final message in List<ChatMessage>.of(_messages)) {
            if (await _isIgnored(message, policy: next)) {
              hidden.add(message.identity);
            }
          }
          await dataService.savePluginSettings('chat', next.toJson());
          preferences = next;
          _hidden
            ..clear()
            ..addAll(hidden);
          if (!_closed) notifyListeners();
        })
        .whenComplete(() => _changingPreferences--);
    _filterTail = saved.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    await saved;
  }

  Future<bool> _isIgnored(
    ChatMessage message, {
    ChatPreferences? policy,
  }) async {
    final settings = policy ?? preferences;
    if (await settings.ignores(message)) return true;
    if (settings.hideCommands) {
      for (final command in commands.commands) {
        if (command.enabled &&
            command.platforms.contains(message.platform) &&
            command.origins.contains(message.origin) &&
            await command.matchAsync(message.text) != null) {
          return true;
        }
      }
    }
    return false;
  }

  void _filterAndDispatch(ChatMessage message, {required bool isPublic}) {
    if (!preferences.hasIgnores && _changingPreferences == 0) {
      _dispatchCommand(message);
      return;
    }
    if (isPublic) _pending.add(message.identity);
    _filterTail = _filterTail.then((_) async {
      var ignored = true;
      try {
        ignored = await _isIgnored(message);
      } catch (failure) {
        error = failure;
      }
      if (_closed) return;
      _pending.remove(message.identity);
      if (ignored && _messages.any((m) => m.identity == message.identity)) {
        _hidden.add(message.identity);
      }
      if (!ignored || !preferences.preventIgnoredCommands) {
        _dispatchCommand(message);
      }
      notifyListeners();
    });
  }

  List<ChatTextPart> messageParts(ChatMessage message) =>
      chatMessageParts(message, emotes);

  Future<void> loadTwitchEmotes() => loadEmotes(ChatPlatform.twitch);
  Future<void> loadEmotes(ChatPlatform platform) async {
    final settings = platform == ChatPlatform.twitch
        ? await loadTwitchChannelSettings(dataService)
        : await dataService.loadPluginSettings('youtube');
    final channel =
        settings[platform == ChatPlatform.twitch
                ? 'broadcasterId'
                : 'channelId']
            ?.toString() ??
        '';
    final token = settings['accessToken']?.toString() ?? '';
    final clientId = settings['clientId']?.toString() ?? '';
    final transport = JsonHttpTransport(
      baseUrl: 'https://api.twitch.tv',
      accessToken: token,
      headers: {'Client-Id': clientId},
    );
    final loaded = await emoteCatalog.load(
      platform,
      channel,
      twitch:
          platform == ChatPlatform.twitch &&
              token.isNotEmpty &&
              clientId.isNotEmpty
          ? (path, query) => transport.request('GET', path, query, null)
          : null,
    );
    if (_closed) return;
    emotes.removeWhere((e) => e.platform == platform);
    emotes.addAll(loaded);
    notifyListeners();
  }

  List<ChatEmote> emotesFor(ChatPlatform platform) {
    final names = <String>{};
    return [
      for (final emote in emotes)
        if (emote.supports(platform) && names.add(emote.name)) emote,
    ];
  }

  List<ChatEmote> suggestEmotes(String prefix, ChatPlatform platform) =>
      emotesFor(platform)
          .where(
            (emote) =>
                emote.supports(platform) &&
                emote.name.toLowerCase().startsWith(prefix.toLowerCase()),
          )
          .take(12)
          .toList();

  List<ChatCompletion> composerCompletions(ChatPlatform platform) => [
    ...chatLocalActions,
    for (final action in actionsFor(ChatActionScope.global, platform))
      ChatCompletion(
        '/action:${action.id}',
        '${action.label} - run automation',
        'action',
      ),
    ...commandCompletions(commands.commands, platform),
    for (final emote in emotesFor(platform))
      ChatCompletion(emote.text, emote.name, 'emote'),
  ];

  Future<void>? _starting;
  Future<void> start() => _starting ??= _start();
  Future<void> _start() async {
    if (_subscriptions.isNotEmpty || _closed) return;
    await refreshIdentities();
    await commands.load();
    try {
      final saved = await dataService.loadPluginSettings('chat');
      if (saved.isNotEmpty ||
          await File(
            '${dataService.settingsDirectory.path}/chat.yaml',
          ).exists()) {
        preferences = ChatPreferences.fromJson(saved);
      }
    } catch (failure) {
      _preferencesValid = false;
      error = failure;
    }
    try {
      final saved = await dataService.loadPluginSettings('chat-actions');
      if (saved.isNotEmpty ||
          await File(
            '${dataService.settingsDirectory.path}/chat-actions.yaml',
          ).exists()) {
        if (saved['version'] != 1) {
          throw const FormatException('Unsupported chat actions version.');
        }
        final actions = (saved['actions'] as List)
            .map(
              (a) => ConfiguredChatAction.fromJson(
                Map<String, dynamic>.from(a as Map),
              ),
            )
            .toList();
        if (actions.length > 100 ||
            actions.map((a) => a.id).toSet().length != actions.length) {
          throw const FormatException('Invalid chat action list.');
        }
        _configuredActions = actions;
      }
    } catch (failure) {
      _actionsValid = false;
      error = failure;
    }
    if (_closed) return;
    for (final platform in ChatPlatform.values) {
      final types = platform == ChatPlatform.twitch
          ? [
              'follow',
              'subscription',
              'giftedSub',
              'redemption',
              'bits',
              'raid',
              'ban',
              'timeout',
            ]
          : ['membership', 'superChat', 'superSticker'];
      for (final type in types) {
        _subscriptions.add(
          eventHub
              .stream(type)
              .listen((values) => _addFeedEvent(platform, type, values)),
        );
      }
    }
    _subscriptions.add(
      eventHub.stream('chat').listen((event) {
        final message = ChatMessage.fromTwitch(
          event,
          botIds: _botIds[ChatPlatform.twitch] ?? {},
        );
        if (message != null) ingest(message);
      }),
    );
    _subscriptions.add(
      eventHub.stream('twitchWhisper').listen((event) {
        final whisper = event['whisper'];
        final text = whisper is Map ? whisper['text'] : null;
        if (text is! String || text.isEmpty) return;
        final message = ChatMessage.fromTwitch(
          {
            ...event,
            'message': text,
            'message_id': event['whisper_id'],
            'chatter_user_id': event['from_user_id'],
            'chatter_user_name': event['from_user_name'],
            'broadcaster_user_id': _twitchChannelId.isEmpty
                ? event['to_user_id']
                : _twitchChannelId,
          },
          origin:
              (_botIds[ChatPlatform.twitch]?.contains(event['to_user_id']) ??
                  false)
              ? ChatOrigin.botWhisper
              : ChatOrigin.whisper,
          botIds: _botIds[ChatPlatform.twitch] ?? {},
        );
        if (message != null) ingest(message);
      }),
    );
    _subscriptions.add(
      eventHub
          .stream('twitchChatDeleted')
          .listen(
            (event) => markDeleted(
              ChatPlatform.twitch,
              '${event['message_id'] ?? ''}',
              channelId: event['broadcaster_user_id']?.toString(),
            ),
          ),
    );
    _subscriptions.add(
      eventHub
          .stream('twitchChatCleared')
          .listen(
            (event) => markUserDeleted(
              ChatPlatform.twitch,
              channelId: event['broadcaster_user_id']?.toString(),
              before: DateTime.tryParse('${event['providerTime'] ?? ''}'),
            ),
          ),
    );
    _subscriptions.add(
      eventHub.stream('twitchUserChatCleared').listen((event) {
        final id = event['target_user_id'];
        if (id is String && id.isNotEmpty) {
          markUserDeleted(
            ChatPlatform.twitch,
            channelId: event['broadcaster_user_id']?.toString(),
            userId: id,
            before: DateTime.tryParse('${event['providerTime'] ?? ''}'),
          );
        }
      }),
    );
    for (final eventId in ['chatMessage', 'superChat', 'superSticker']) {
      _subscriptions.add(
        eventHub.stream(eventId).listen((event) {
          final snippet = event['snippet'];
          if (snippet is Map && snippet['type'] == 'tombstone') {
            markDeleted(
              ChatPlatform.youtube,
              '${event['id'] ?? ''}',
              channelId: snippet['liveChatId']?.toString() ?? _liveChatId,
            );
            return;
          }
          if (snippet is Map && snippet['type'] == 'userBannedEvent') {
            final details = snippet['userBannedDetails'];
            final banned = details is Map ? details['bannedUserDetails'] : null;
            final id = banned is Map ? banned['channelId'] : null;
            if (id is String && id.isNotEmpty) {
              markUserDeleted(
                ChatPlatform.youtube,
                channelId: snippet['liveChatId']?.toString() ?? _liveChatId,
                userId: id,
                before: DateTime.tryParse('${snippet['publishedAt'] ?? ''}'),
              );
            }
            return;
          }
          if (snippet is Map && snippet['type'] == 'messageDeletedEvent') {
            final details = snippet['messageDeletedDetails'];
            if (details is Map) {
              markDeleted(
                ChatPlatform.youtube,
                details['deletedMessageId']?.toString() ?? '',
                channelId: snippet['liveChatId']?.toString() ?? _liveChatId,
              );
            }
            return;
          }
          final message = ChatMessage.fromYouTube(
            event,
            botIds: _botIds[ChatPlatform.youtube] ?? {},
            liveChatId: _liveChatId,
          );
          if (message != null) ingest(message);
        }),
      );
    }
  }

  Future<void> refreshIdentities() async {
    final twitch = await loadTwitchChannelSettings(dataService);
    final bot = await TwitchAccountAuthService(
      dataService: dataService,
    ).loadAccount('bot');
    final youtube = await dataService.loadPluginSettings('youtube');
    _twitchChannelId = twitch['broadcasterId']?.toString() ?? '';
    _botIds[ChatPlatform.twitch] = {
      if (bot?.config['twitchId'] case final String id when id.isNotEmpty) id,
      if (twitch['moderatorId'] case final String id
          when id.isNotEmpty && id != _twitchChannelId)
        id,
    };
    _botIds[ChatPlatform.youtube] = {
      if (youtube['channelId'] case final String id when id.isNotEmpty) id,
    };
    _liveChatId =
        youtubeLiveChatId?.call() ?? youtube['liveChatId']?.toString() ?? '';
  }

  void ingest(ChatMessage message) {
    if (_closed) return;
    if (message.id.isNotEmpty && !_seen.add(message.identity)) return;
    if (_seen.length > 4096) _seen.remove(_seen.first);
    if (message.origin == ChatOrigin.whisper ||
        message.origin == ChatOrigin.botWhisper) {
      _filterAndDispatch(message, isPublic: false);
      return; // Private inputs never enter the public history, dock or overlay.
    }
    final room = '${message.platform.name}:${message.channelId}';
    final cutoff = [
      _clearBefore['$room:*'],
      _clearBefore['$room:${message.userId}'],
    ].nonNulls;
    if (_deletedIds.contains('$room:${message.id}') ||
        _deletedIds.contains('${message.platform.name}:*:${message.id}') ||
        (message.publishedAt != null &&
            cutoff.any((time) => !message.publishedAt!.isAfter(time)))) {
      message = message.markDeleted();
    }
    _messages.add(message);
    while (_messages.length > historyLimit) {
      final removed = _messages.removeAt(0);
      _hidden.remove(removed.identity);
      _pending.remove(removed.identity);
    }
    _filterAndDispatch(message, isPublic: true);
    notifyListeners();
  }

  void _dispatchCommand(ChatMessage message) {
    unawaited(
      commands.handle(message).catchError((Object failure) {
        error = failure;
        if (!_closed) notifyListeners();
      }),
    );
  }

  void clearHistory() {
    _messages.clear();
    _events.clear();
    _hidden.clear();
    _pending.clear();
    notifyListeners();
  }

  void markUserDeleted(
    ChatPlatform platform, {
    String? channelId,
    String? userId,
    DateTime? before,
  }) {
    if (channelId == null || channelId.isEmpty) return;
    final cutoff = before ?? DateTime.now();
    final key = '${platform.name}:$channelId:${userId ?? '*'}';
    if (_clearBefore[key] == null || _clearBefore[key]!.isBefore(cutoff)) {
      _clearBefore[key] = cutoff;
    }
    if (_clearBefore.length > 4096) {
      _clearBefore.remove(_clearBefore.keys.first);
    }
    for (var i = 0; i < _messages.length; i++) {
      final message = _messages[i];
      if (message.platform == platform &&
          message.channelId == channelId &&
          (userId == null || message.userId == userId) &&
          (message.publishedAt == null ||
              !message.publishedAt!.isAfter(cutoff))) {
        _messages[i] = message.markDeleted();
      }
    }
    if (!_closed) notifyListeners();
  }

  void markDeleted(ChatPlatform platform, String id, {String? channelId}) {
    if (id.isEmpty) return;
    _deletedIds.add('${platform.name}:${channelId ?? '*'}:$id');
    if (_deletedIds.length > 4096) _deletedIds.remove(_deletedIds.first);
    for (var i = 0; i < _messages.length; i++) {
      final message = _messages[i];
      if (message.platform == platform &&
          message.id == id &&
          (channelId == null || message.channelId == channelId)) {
        _messages[i] = message.markDeleted();
      }
    }
    if (!_closed) notifyListeners();
  }

  Future<void> send(ChatPlatform platform, String text) async {
    final message = text.trim();
    if (message.startsWith('/action:')) {
      final token = message.split(RegExp(r'\s')).first;
      return runConfiguredAction(
        token.substring('/action:'.length),
        platform: platform,
        input: message.substring(token.length).trimLeft(),
      );
    }
    if (message.isEmpty) throw const FormatException('Enter a chat message.');
    if (message.length > (platform == ChatPlatform.twitch ? 500 : 200)) {
      throw const FormatException('Message exceeds the platform limit.');
    }
    await refreshIdentities();
    final registry = await registryFuture;
    final twitch = platform == ChatPlatform.twitch
        ? await loadTwitchChannelSettings(dataService)
        : <String, dynamic>{};
    final config = platform == ChatPlatform.twitch
        ? {
            'broadcasterId': twitch['broadcasterId'],
            // The configured registry authenticates using the channel account.
            'moderatorId': twitch['broadcasterId'],
            'message': message,
          }
        : {'liveChatId': _liveChatId, 'message': message};
    if (platform == ChatPlatform.youtube && _liveChatId.isEmpty) {
      throw StateError('Connect a YouTube live chat first.');
    }
    // Never echo locally: provider delivery owns history, avoiding duplicates and false success.
    await registry.invokeActionKey(
      ActionKey(
        plugin: PluginId(platform.name),
        action: ActionId(
          platform == ChatPlatform.twitch ? 'chat' : 'sendChatMessage',
        ),
      ),
      config,
    );
  }

  Future<void> quickAction(ChatMessage message, ChatQuickAction action) async {
    if (message.userId.isEmpty) {
      throw StateError('This message has no provider user ID.');
    }
    if (action == ChatQuickAction.deleteMessage && message.id.isEmpty) {
      throw StateError('This message has no provider message ID.');
    }
    if (message.isBroadcaster && action != ChatQuickAction.deleteMessage) {
      throw StateError('The channel owner cannot be banned or timed out.');
    }
    final registry = await registryFuture;
    final settings = message.platform == ChatPlatform.twitch
        ? await loadTwitchChannelSettings(dataService)
        : <String, dynamic>{};
    final actionId = message.platform == ChatPlatform.twitch
        ? switch (action) {
            ChatQuickAction.deleteMessage => 'deleteMessage',
            ChatQuickAction.timeout => 'timeout',
            ChatQuickAction.ban => 'ban',
            ChatQuickAction.unban => 'unban',
          }
        : switch (action) {
            ChatQuickAction.deleteMessage => 'deleteMessage',
            ChatQuickAction.timeout || ChatQuickAction.ban => 'banUser',
            ChatQuickAction.unban => throw StateError(
              'YouTube unban requires the ban ID, available in the YouTube workspace.',
            ),
          };
    await registry.invokeActionKey(
      ActionKey(
        plugin: PluginId(message.platform.name),
        action: ActionId(actionId),
      ),
      {
        'broadcasterId': message.channelId.isNotEmpty
            ? message.channelId
            : settings['broadcasterId'],
        'moderatorId': settings['broadcasterId'],
        'messageId': message.id,
        'viewerId': message.userId,
        'channelId': message.userId,
        'liveChatId': message.channelId.isNotEmpty
            ? message.channelId
            : _liveChatId,
        if (action == ChatQuickAction.timeout) 'duration': 60,
        'banDurationSeconds': action == ChatQuickAction.timeout ? 60 : 0,
        'reason': '',
      },
    );
    if (action == ChatQuickAction.deleteMessage) {
      markDeleted(message.platform, message.id, channelId: message.channelId);
    }
  }

  Future<void> close() async {
    _closed = true;
    try {
      await _starting;
    } catch (_) {
      /* Startup errors remain visible to the caller. */
    }
    await Future.wait(_subscriptions.map((s) => s.cancel()));
    _subscriptions.clear();
    await _filterTail;
    await commands.close();
    dispose();
  }
}
