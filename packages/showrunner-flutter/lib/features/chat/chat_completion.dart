import 'chat_command.dart';
import 'chat_message.dart';

final class ChatCompletion {
  const ChatCompletion(this.text, this.label, this.kind);
  final String text, label, kind;
  Map<String, String> toJson() => {'text': text, 'label': label, 'kind': kind};
}

const chatLocalActions = [
  ChatCompletion('/clear', '/clear - clear local history', 'action'),
  ChatCompletion('/pause', '/pause - pause this view', 'action'),
  ChatCompletion('/resume', '/resume - show incoming messages', 'action'),
];

List<ChatCompletion> commandCompletions(
  Iterable<ChatCommand> commands,
  ChatPlatform platform,
) => [
  for (final command in commands)
    if (command.enabled &&
        command.includeInList &&
        command.platforms.contains(platform) &&
        command.origins.contains(ChatOrigin.chat) &&
        command.matchMode != CommandMatchMode.regex)
      for (final text in [command.pattern, ...command.aliases])
        if (text.startsWith('!'))
          ChatCompletion(text, '$text - ${command.name}', 'command'),
];
