import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/chat/chat_emote.dart';
import 'package:showrunner_flutter/features/chat/chat_emote_catalog.dart';
import 'package:showrunner_flutter/features/chat/chat_message.dart';
import 'package:showrunner_flutter/features/chat/chat_message_body.dart';

void main() {
  test(
    'provider catalogs parse static and animated images without accepting arbitrary hosts',
    () {
      final twitch = parseTwitchEmotes({
        'data': [
          {
            'id': '123',
            'name': 'TwitchProbe',
            'format': ['static', 'animated'],
          },
        ],
      });
      expect(twitch.single.image(animate: true), contains('/animated/'));
      expect(twitch.single.image(animate: false), contains('/static/'));
      final bttv = parseBttvEmotes({
        'channelEmotes': [
          {'id': 'abc', 'code': 'BttvProbe', 'imageType': 'gif'},
        ],
      }, platform: ChatPlatform.youtube);
      expect(bttv.single.supports(ChatPlatform.youtube), isTrue);
      expect(bttv.single.image(animate: false), isNull);
      final ffz = parseFfzEmotes({
        'default_sets': [1],
        'sets': {
          '1': {
            'emoticons': [
              {
                'name': 'FfzProbe',
                'urls': {'1': '//cdn.frankerfacez.com/emoticon/123/1'},
              },
            ],
          },
          '2': {
            'emoticons': [
              {
                'name': 'Excluded',
                'urls': {'1': 'https://untrusted.example/image.png'},
              },
            ],
          },
        },
      });
      expect(
        ffz.single.image(animate: false),
        startsWith('https://cdn.frankerfacez.com/'),
      );
      final seven = parseSevenTvEmotes({
        'emote_set': {
          'emotes': [
            {
              'name': 'SevenProbe',
              'data': {
                'animated': true,
                'host': {
                  'url': '//cdn.7tv.app/emote/abc',
                  'files': [
                    {'name': '1x.webp'},
                    {'name': '1x_static.webp'},
                  ],
                },
              },
            },
          ],
        },
      }, platform: ChatPlatform.twitch);
      expect(seven.single.image(animate: false), endsWith('1x_static.webp'));
      expect(chatImageUrl('javascript:alert(1)'), isNull);
      expect(
        chatImageUrl('https://cdn.7tv.app.evil.example/image.webp'),
        isNull,
      );
      expect(chatImageUrl('https://user:pass@cdn.7tv.app/image.webp'), isNull);
      expect(chatImageUrl('http://cdn.7tv.app/image.webp'), isNull);
    },
  );
  test(
    'catalog cache bounds public requests and provider failure does not discard others',
    () async {
      var requests = 0;
      var now = DateTime.utc(2026);
      final catalog = ChatEmoteCatalog(
        now: () => now,
        get: (uri) async {
          requests++;
          if (uri.host == '7tv.io') {
            throw StateError('isolated unavailable provider');
          }
          if (uri.path.endsWith('/global') && uri.host == 'api.betterttv.net') {
            return [
              {'id': 'abc', 'code': 'GlobalProbe', 'imageType': 'png'},
            ];
          }
          return {};
        },
      );
      final first = await catalog.load(ChatPlatform.twitch, '123');
      expect(first.single.name, 'GlobalProbe');
      expect(requests, 6);
      expect(catalog.status['7TV global'], 'unavailable');
      await catalog.load(ChatPlatform.twitch, '123');
      expect(requests, 8); // Only failed requests retry.
      now = now.add(const Duration(minutes: 16));
      await catalog.load(ChatPlatform.twitch, '123');
      expect(requests, 14);
    },
  );
  test(
    'message fragments preserve punctuation, text and channel/platform scopes',
    () {
      final message = ChatMessage.fromTwitch({
        'message_id': 'm',
        'chatter_user_id': 'u',
        'broadcaster_user_id': 'c',
        'message': {
          'text': 'Hello TwitchProbe! SevenProbe',
          'fragments': [
            {'type': 'text', 'text': 'Hello '},
            {
              'type': 'emote',
              'text': 'TwitchProbe',
              'emote': {
                'id': '123',
                'format': ['static'],
              },
            },
            {'type': 'text', 'text': '! SevenProbe'},
          ],
        },
      })!;
      const seven = ChatEmote(
        'SevenProbe',
        'SevenProbe',
        platform: ChatPlatform.twitch,
        channelId: 'c',
        imageUrl: 'https://cdn.7tv.app/emote/abc/1x.webp',
      );
      final parts = chatMessageParts(message, [seven]);
      expect(parts.map((p) => p.text).join(), message.text);
      expect(parts.where((p) => p.emote != null), hasLength(2));
      expect(
        chatMessageParts(message, [
          const ChatEmote(
            'SevenProbe',
            'SevenProbe',
            platform: ChatPlatform.youtube,
          ),
        ]).where((p) => p.emote != null),
        hasLength(1),
      );
      expect(
        chatMessageParts(message.markDeleted(), [seven]).single.text,
        'Message deleted',
      );
    },
  );
  testWidgets(
    'rich text uses images with semantic fallback and honors disabled animation',
    (tester) async {
      const emote = ChatEmote(
        'Animated',
        'Animated',
        animated: true,
        imageUrl: 'https://cdn.betterttv.net/emote/abc/1x',
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatMessageBody(
              parts: [ChatTextPart('Animated', emote)],
              animate: false,
              style: TextStyle(fontSize: 14),
            ),
          ),
        ),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.text('Animated'), findsOneWidget);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatMessageBody(
              parts: [ChatTextPart('Animated', emote)],
              animate: true,
              style: TextStyle(fontSize: 14),
            ),
          ),
        ),
      );
      expect(
        tester.widget<Image>(find.byType(Image)).semanticLabel,
        'Animated',
      );
    },
  );
}
