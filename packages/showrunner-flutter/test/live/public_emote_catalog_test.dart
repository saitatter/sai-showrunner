import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/chat/chat_emote.dart';
import 'package:showrunner_flutter/features/chat/chat_emote_catalog.dart';
import 'package:showrunner_flutter/features/chat/chat_message.dart';
import 'package:showrunner_flutter/services/http_provider_transports.dart';

/// Opt-in public GETs only: no OAuth, channel data, sends or moderation.
void main() {
  const live = bool.fromEnvironment('SHOWRUNNER_LIVE_PUBLIC_EMOTES');
  final sources = <String, (String, String, List<ChatEmote> Function(Object?))>{
    '7TV': (
      'https://7tv.io',
      '/v3/emote-sets/global',
      (json) => parseSevenTvEmotes(json, platform: ChatPlatform.twitch),
    ),
    'BTTV': (
      'https://api.betterttv.net',
      '/3/cached/emotes/global',
      (json) => parseBttvEmotes(json, platform: ChatPlatform.twitch),
    ),
    'FFZ': ('https://api.frankerfacez.com', '/v1/set/global', parseFfzEmotes),
  };
  for (final source in sources.entries) {
    test(
      '${source.key} public global catalog uses the current provider response',
      () async {
        final json = await JsonHttpTransport(
          baseUrl: source.value.$1,
          timeout: const Duration(seconds: 10),
          maxRetries: 0,
        ).requestValue('GET', source.value.$2, {}, null);
        final emotes = source.value.$3(json);
        expect(emotes, isNotEmpty);
        expect(
          emotes.every(
            (e) => e.name.isNotEmpty && e.image(animate: true) != null,
          ),
          isTrue,
        );
      },
      skip: live
          ? false
          : 'Opt in with --dart-define=SHOWRUNNER_LIVE_PUBLIC_EMOTES=true',
    );
  }
}
