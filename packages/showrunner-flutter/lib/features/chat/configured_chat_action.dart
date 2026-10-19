import 'chat_message.dart';

enum ChatActionScope { global, message, user, event }

final class ConfiguredChatAction {
  ConfiguredChatAction({
    required this.id,
    required this.label,
    required this.automationFile,
    this.queueId = 'default',
    this.scope = ChatActionScope.message,
    this.enabled = true,
    this.icon = 'play',
    this.color = 'default',
    Set<ChatPlatform> platforms = const {
      ChatPlatform.twitch,
      ChatPlatform.youtube,
    },
    Map<String, String> arguments = const {},
  }) : platforms = Set.unmodifiable(platforms),
       arguments = Map.unmodifiable(arguments) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(id) ||
        label.trim().isEmpty ||
        label.length > 100 ||
        automationFile.isEmpty ||
        automationFile.contains(RegExp(r'[/\\]')) ||
        !automationFile.endsWith('.yaml') ||
        queueId.trim().isEmpty ||
        platforms.isEmpty ||
        arguments.length > 32 ||
        arguments.entries.any(
          (e) => e.key.isEmpty || e.key.length > 80 || e.value.length > 2000,
        ) ||
        !['play', 'star', 'chat', 'person', 'bolt'].contains(icon) ||
        ![
          'default',
          'purple',
          'blue',
          'green',
          'orange',
          'red',
        ].contains(color)) {
      throw const FormatException('Invalid chat action settings.');
    }
  }
  final String id, label, automationFile, queueId, icon, color;
  final ChatActionScope scope;
  final bool enabled;
  final Set<ChatPlatform> platforms;
  final Map<String, String> arguments;
  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'automationFile': automationFile,
    'queueId': queueId,
    'scope': scope.name,
    'enabled': enabled,
    'icon': icon,
    'color': color,
    'platforms': platforms.map((p) => p.name).toList(),
    'arguments': arguments,
  };
  factory ConfiguredChatAction.fromJson(Map<String, dynamic> json) =>
      ConfiguredChatAction(
        id: json['id'] as String,
        label: json['label'] as String,
        automationFile: json['automationFile'] as String,
        queueId: json['queueId'] as String,
        scope: ChatActionScope.values.byName(json['scope'] as String),
        enabled: json['enabled'] as bool,
        icon: json['icon'] as String,
        color: json['color'] as String,
        platforms: (json['platforms'] as List)
            .cast<String>()
            .map(ChatPlatform.values.byName)
            .toSet(),
        arguments: Map<String, String>.from(json['arguments'] as Map),
      );
}

final class ChatFeedEvent {
  ChatFeedEvent({
    required this.id,
    required this.platform,
    required this.type,
    required this.time,
    required this.userId,
    required this.userName,
    required this.message,
  });
  final String id, type, userId, userName, message;
  final DateTime time;
  final ChatPlatform platform;
  Map<String, dynamic> get context => {
    'eventId': id,
    'eventType': type,
    'platform': platform.name,
    'viewerId': userId,
    'viewerName': userName,
    'message': message,
    'time': time.toUtc().toIso8601String(),
  };
}
