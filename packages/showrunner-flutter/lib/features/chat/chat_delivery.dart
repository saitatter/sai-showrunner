import 'chat_message.dart';

enum ChatSendAccount { broadcaster, bot }

/// Per-platform outcomes let the composer retry failed destinations without
/// repeating successful deliveries. Provider exceptions never enter this model.
final class ChatDeliveryResult {
  ChatDeliveryResult(Map<ChatPlatform, bool> delivered)
    : delivered = Map.unmodifiable(delivered);
  final Map<ChatPlatform, bool> delivered;
  bool get succeeded =>
      delivered.isNotEmpty && delivered.values.every((v) => v);
  Set<ChatPlatform> get failed => {
    for (final entry in delivered.entries)
      if (!entry.value) entry.key,
  };
}
