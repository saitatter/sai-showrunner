import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/chat/chat_message.dart';
import 'package:showrunner_flutter/features/chat/chat_preferences.dart';

void main() {
  ChatMessage message(
    String text, {
    ChatPlatform platform = ChatPlatform.twitch,
  }) => ChatMessage(
    platform: platform,
    id: '1',
    channelId: 'c',
    userId: '42',
    userName: 'Name',
    text: text,
    receivedAt: DateTime.utc(2026),
  );
  test(
    'preferences round trip and reject unsupported versions and invalid limits',
    () {
      final preferences = ChatPreferences(
        fontSize: 18,
        font: 'monospace',
        timestamps: true,
        ignoredUsers: {'twitch:42'},
        highlightedUsers: {'youtube:42'},
        highlightTerms: ['@channel'],
        ignoreRules: [ChatIgnoreRule(ChatRuleMode.prefix, '!spam')],
      );
      expect(
        ChatPreferences.fromJson(preferences.toJson()).toJson(),
        preferences.toJson(),
      );
      expect(
        () => ChatPreferences.fromJson({...preferences.toJson(), 'version': 9}),
        throwsFormatException,
      );
      expect(
        () => ChatPreferences(fontSize: double.nan),
        throwsFormatException,
      );
      expect(() => ChatPreferences(fontSize: 80), throwsFormatException);
      expect(
        () => ChatPreferences(ignoredUsers: {'42'}),
        throwsFormatException,
      );
      expect(
        () => ChatIgnoreRule(ChatRuleMode.regex, '['),
        throwsFormatException,
      );
      expect(
        () => ChatPreferences(
          ignoreRules: List.generate(
            33,
            (_) => ChatIgnoreRule(ChatRuleMode.contains, 'spam'),
          ),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'ignore identities are platform scoped and literal rules do not interpret regex',
    () async {
      final preferences = ChatPreferences(
        ignoredUsers: {'twitch:42'},
        highlightedUsers: {'youtube:42'},
        highlightTerms: ['@CHANNEL'],
      );
      expect(await preferences.ignores(message('hi')), isTrue);
      expect(
        await preferences.ignores(
          message('hi', platform: ChatPlatform.youtube),
        ),
        isFalse,
      );
      expect(
        preferences.highlights(message('hi', platform: ChatPlatform.youtube)),
        isTrue,
      );
      expect(preferences.highlights(message('hello @channel')), isTrue);
      expect(
        preferences.highlights(message('hello @channel').markDeleted()),
        isFalse,
      );
      final literal = ChatIgnoreRule(ChatRuleMode.contains, '.*');
      expect(await literal.matches('anything'), isFalse);
      expect(await literal.matches('literal .* characters'), isTrue);
    },
  );
}
