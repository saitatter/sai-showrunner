import 'chat_message.dart';
import 'unified_chat_runtime.dart';
import 'chat_preferences.dart';

final class ChatDockProtocolException implements Exception {
  const ChatDockProtocolException(this.code, [this.status = 400]);
  final String code;
  final int status;
}

sealed class ChatDockRequest {
  const ChatDockRequest();
  Future<void> execute(UnifiedChatRuntime runtime);

  static ChatDockRequest parse(String path, Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const ChatDockProtocolException('invalid_payload');
    }
    final allowed = switch (path) {
      '/api/send' => {'platform', 'message'},
      '/api/configured-action' => {'id', 'platform', 'identity', 'eventId'},
      '/api/action' => {'identity', 'action'},
      '/api/clear' => <String>{},
      '/api/preferences' => null,
      _ => throw const ChatDockProtocolException('not_found', 404),
    };
    if (allowed != null && value.keys.any((key) => !allowed.contains(key))) {
      throw const ChatDockProtocolException('invalid_payload');
    }
    String text(String key, [int max = 512]) {
      final field = value[key];
      if (field is! String || field.trim().isEmpty || field.length > max) {
        throw const ChatDockProtocolException('invalid_payload');
      }
      return field;
    }

    String? optional(String key) => value[key] == null ? null : text(key);
    ChatPlatform platform() {
      final name = text('platform', 16);
      return ChatPlatform.values
              .where((entry) => entry.name == name)
              .firstOrNull ??
          (throw const ChatDockProtocolException('invalid_platform'));
    }

    switch (path) {
      case '/api/send':
        final target = platform();
        final message = text(
          'message',
          target == ChatPlatform.twitch ? 500 : 200,
        );
        return ChatDockSend(target, message);
      case '/api/configured-action':
        return ChatDockConfiguredAction(
          text('id', 128),
          platform(),
          optional('identity'),
          optional('eventId'),
        );
      case '/api/action':
        final name = text('action', 32);
        final action = ChatQuickAction.values
            .where((entry) => entry.name == name)
            .firstOrNull;
        if (action == null) {
          throw const ChatDockProtocolException('invalid_action');
        }
        return ChatDockAction(text('identity'), action);
      case '/api/clear':
        return const ChatDockClear();
      case '/api/preferences':
        if (value['version'] != 1) {
          throw const ChatDockProtocolException('unsupported_preferences');
        }
        try {
          final fields = ChatPreferences().toJson();
          if (value.keys.any((key) => !fields.containsKey(key))) {
            throw const ChatDockProtocolException('invalid_preferences');
          }
          return ChatDockPreferences(ChatPreferences.fromJson(value));
        } on Object {
          throw const ChatDockProtocolException('invalid_preferences');
        }
      default:
        throw const ChatDockProtocolException('not_found', 404);
    }
  }
}

final class ChatDockSend extends ChatDockRequest {
  const ChatDockSend(this.platform, this.message);
  final ChatPlatform platform;
  final String message;
  @override
  Future<void> execute(UnifiedChatRuntime runtime) =>
      runtime.send(platform, message);
}

final class ChatDockConfiguredAction extends ChatDockRequest {
  const ChatDockConfiguredAction(
    this.id,
    this.platform,
    this.identity,
    this.eventId,
  );
  final String id;
  final ChatPlatform platform;
  final String? identity, eventId;
  @override
  Future<void> execute(UnifiedChatRuntime runtime) =>
      runtime.runConfiguredAction(
        id,
        platform: platform,
        messageIdentity: identity,
        eventId: eventId,
      );
}

final class ChatDockAction extends ChatDockRequest {
  const ChatDockAction(this.identity, this.action);
  final String identity;
  final ChatQuickAction action;
  @override
  Future<void> execute(UnifiedChatRuntime runtime) async {
    final target = runtime.messages
        .where((message) => message.identity == identity)
        .firstOrNull;
    if (target == null) {
      throw const ChatDockProtocolException('target_not_found', 404);
    }
    await runtime.quickAction(target, action);
  }
}

final class ChatDockClear extends ChatDockRequest {
  const ChatDockClear();
  @override
  Future<void> execute(UnifiedChatRuntime runtime) async {
    runtime.clearHistory();
  }
}

final class ChatDockPreferences extends ChatDockRequest {
  const ChatDockPreferences(this.preferences);
  final ChatPreferences preferences;
  @override
  Future<void> execute(UnifiedChatRuntime runtime) =>
      runtime.savePreferences(preferences);
}

/// Public chat projection; provider source payloads stay inside the runtime.
Map<String, dynamic> chatDockSnapshot(UnifiedChatRuntime runtime) => {
  'preferences': runtime.preferences.toJson(),
  'events': runtime.events.map((e) => e.context).toList(),
  'actions': [
    for (final action in runtime.configuredActions)
      if (action.enabled)
        {
          'id': action.id,
          'label': action.label,
          'scope': action.scope.name,
          'platforms': action.platforms.map((p) => p.name).toList(),
          'icon': action.icon,
          'color': action.color,
        },
  ],
  'messages': runtime.messages
      .where(
        (message) =>
            message.origin != ChatOrigin.whisper &&
            message.origin != ChatOrigin.botWhisper,
      )
      .map(
        (m) => {
          'identity': m.identity,
          ...m.context,
          'deleted': m.deleted,
          'parts': runtime
              .messageParts(m)
              .map(
                (part) =>
                    part.toJson(animate: runtime.preferences.animatedEmotes),
              )
              .toList(),
          'highlighted': runtime.preferences.highlights(m),
          'time': m.receivedAt.toUtc().toIso8601String(),
        },
      )
      .toList(),
  'completions': {
    for (final platform in ChatPlatform.values)
      platform.name: runtime
          .composerCompletions(platform)
          .map((s) => s.toJson())
          .toList(),
  },
  'emotes': runtime.emotes
      .map((e) => e.toJson(animate: runtime.preferences.animatedEmotes))
      .toList(),
};
