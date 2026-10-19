import 'chat_command.dart';

/// Stateless filtering for raw chat triggers. Managed cooldowns/counters belong
/// to ChatCommandManager, rather than a graph definition or a trigger callback.
final class ChatTriggerFilter {
  ChatTriggerFilter(this.source) {
    final raw = source['command'];
    if (raw != null && raw is! Map) {
      throw const FormatException('Invalid chat command filter.');
    }
    if (raw is Map) {
      final pattern = raw['match'];
      if (pattern != null && pattern is! String) {
        throw const FormatException('A command match must be text.');
      }
      if ((pattern == null || (pattern as String).trim().isEmpty) &&
          (raw['aliases'] as List? ?? []).isNotEmpty) {
        throw const FormatException('Aliases require a command match value.');
      }
      CommandMatchMode.values.byName(raw['mode']?.toString() ?? 'command');
    }
    if (source['cooldown'] != null) {
      throw const FormatException('Configure cooldowns in Chat Commands.');
    }
  }
  final Map<String, dynamic> source;
  bool matches(String text) {
    final raw = source['command'];
    if (raw is! Map) return true;
    final pattern = raw['match'] as String?;
    // Empty optional filters accept all messages, including a new node's schema defaults.
    if (pattern == null || pattern.trim().isEmpty) return true;
    final match = matchCommandText(
      text,
      [pattern, ...?((raw['aliases'] as List?)?.cast<String>())],
      mode: CommandMatchMode.values.byName(
        raw['mode']?.toString() ?? 'command',
      ),
      caseSensitive: raw['caseSensitive'] == true,
    );
    return match != null &&
        (raw['hasMessage'] != true || match.argumentText.isNotEmpty);
  }
}
