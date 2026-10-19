import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../plugins/registry/plugin_registry.dart';
import '../../plugins/twitch/account_runtime.dart';
import '../../services/plugin_event_hub.dart';
import '../../services/showrunner_data_service.dart';
import '../../services/http_provider_transports.dart';
import 'chat_message.dart';
import 'command_manager.dart';

enum ChatQuickAction { deleteMessage, timeout, ban, unban }

final class ChatEmote {
  const ChatEmote(this.name, this.text);
  final String name, text;
}

final class UnifiedChatRuntime extends ChangeNotifier {
  UnifiedChatRuntime({
    required this.eventHub,
    required this.dataService,
    required this.registryFuture,
    required this.commands,
    this.youtubeLiveChatId,
    this.historyLimit = 500,
  });

  final DartPluginEventHub eventHub;
  final ShowRunnerDataService dataService;
  final Future<DartPluginRegistry> registryFuture;
  final ChatCommandManager commands;
  final String? Function()? youtubeLiveChatId;
  final int historyLimit;
  final _subscriptions = <StreamSubscription<Map<String, dynamic>>>[];
  final _messages = <ChatMessage>[];
  final _seen = <String>{};
  final _botIds = <ChatPlatform, Set<String>>{};
  String _liveChatId = '';
  String _twitchChannelId = '';
  bool _closed = false;
  Object? error;
  final List<ChatEmote> emotes = [
    const ChatEmote(':smile:', '😀'),
    const ChatEmote(':heart:', '❤️'),
    const ChatEmote(':wave:', '👋'),
    const ChatEmote(':party:', '🎉'),
  ];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  Future<void> loadTwitchEmotes() async {
    final settings = await loadTwitchChannelSettings(dataService);
    final token = settings['accessToken']?.toString() ?? '';
    final clientId = settings['clientId']?.toString() ?? '';
    final channel = settings['broadcasterId']?.toString() ?? '';
    if (token.isEmpty || clientId.isEmpty || channel.isEmpty) {
      throw StateError('Connect Twitch before loading its emotes.');
    }
    final transport = JsonHttpTransport(
      baseUrl: 'https://api.twitch.tv',
      accessToken: token,
      headers: {'Client-Id': clientId},
    );
    final responses = await Future.wait([
      transport.request('GET', '/helix/chat/emotes/global', {}, null),
      transport.request('GET', '/helix/chat/emotes', {
        'broadcaster_id': channel,
      }, null),
    ]);
    final names = <String>{};
    for (final response in responses) {
      for (final item in (response['data'] as List? ?? []).whereType<Map>()) {
        final name = item['name'];
        if (name is String && name.isNotEmpty) names.add(name);
      }
    }
    if (_closed) return;
    emotes.removeWhere((e) => !e.name.startsWith(':'));
    emotes.addAll(
      (names.toList()..sort()).map((name) => ChatEmote(name, name)),
    );
    notifyListeners();
  }

  List<ChatEmote> suggestEmotes(String prefix, ChatPlatform platform) => emotes
      .where(
        (emote) =>
            (platform == ChatPlatform.twitch || emote.name.startsWith(':')) &&
            emote.name.toLowerCase().startsWith(prefix.toLowerCase()),
      )
      .take(12)
      .toList();

  Future<void>? _starting;
  Future<void> start() => _starting ??= _start();
  Future<void> _start() async {
    if (_subscriptions.isNotEmpty || _closed) return;
    await refreshIdentities();
    await commands.load();
    if (_closed) return;
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
            ),
          ),
    );
    _subscriptions.add(
      eventHub
          .stream('twitchUserChatCleared')
          .listen(
            (event) => markUserDeleted(
              ChatPlatform.twitch,
              channelId: event['broadcaster_user_id']?.toString(),
              userId: event['target_user_id']?.toString(),
            ),
          ),
    );
    for (final eventId in ['chatMessage', 'superChat', 'superSticker']) {
      _subscriptions.add(
        eventHub.stream(eventId).listen((event) {
          final snippet = event['snippet'];
          if (snippet is Map && snippet['type'] == 'messageDeletedEvent') {
            final details = snippet['messageDeletedDetails'];
            if (details is Map) {
              markDeleted(
                ChatPlatform.youtube,
                details['deletedMessageId']?.toString() ?? '',
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
      _dispatchCommand(message);
      return; // Private inputs never enter the public history, dock or overlay.
    }
    _messages.add(message);
    while (_messages.length > historyLimit) {
      _messages.removeAt(0);
    }
    notifyListeners();
    _dispatchCommand(message);
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
    notifyListeners();
  }

  void markUserDeleted(
    ChatPlatform platform, {
    String? channelId,
    String? userId,
  }) {
    if (channelId == null || channelId.isEmpty) return;
    for (var i = 0; i < _messages.length; i++) {
      final message = _messages[i];
      if (message.platform == platform &&
          message.channelId == channelId &&
          (userId == null || message.userId == userId)) {
        _messages[i] = message.markDeleted();
      }
    }
    if (!_closed) notifyListeners();
  }

  void markDeleted(ChatPlatform platform, String id, {String? channelId}) {
    if (id.isEmpty) return;
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
      markDeleted(message.platform, message.id);
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
    await commands.close();
    dispose();
  }
}
