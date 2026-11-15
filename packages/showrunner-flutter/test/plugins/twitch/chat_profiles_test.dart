import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/twitch/chat_profiles.dart';
import 'package:showrunner_flutter/plugins/twitch/event_parser.dart';
import 'package:showrunner_flutter/plugins/youtube/chat_profiles.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  late Directory root;
  late ShowRunnerDataService data;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('chat-public-profiles-');
    data = ShowRunnerDataService(root);
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'public Twitch profiles filter private fields and preserve badge versions',
    () async {
      final paths = <String>[];
      final source = TwitchChatMetadataSource(
        dataService: data,
        request: (method, path, query, body) async {
          expect(method, 'GET');
          expect(body, isEmpty);
          paths.add(path);
          if (path == '/helix/users') {
            expect(query, {
              'id': ['viewer'],
            });
            return {
              'data': [
                {
                  'id': 'viewer',
                  'display_name': 'Viewer',
                  'login': 'viewer',
                  'profile_image_url':
                      'https://static-cdn.jtvnw.net/avatar.png',
                  'email': 'private@example.test',
                  'accessToken': 'private-token',
                },
                {'id': 'unrequested', 'display_name': 'Other'},
              ],
            };
          }
          return {
            'data': [
              {
                'set_id': 'subscriber',
                'versions': [
                  {
                    'id': '12',
                    'title': 'One year',
                    'image_url_1x':
                        'https://static-cdn.jtvnw.net/${query.isEmpty ? 'global' : 'channel'}.png',
                  },
                ],
              },
            ],
          };
        },
      );
      addTearDown(source.close);
      final metadata = await source.load({'viewer'}, {'channel'});
      expect(paths, [
        '/helix/users',
        '/helix/chat/badges/global',
        '/helix/chat/badges',
      ]);
      expect(metadata.users.keys, ['viewer']);
      expect(
        metadata.users['viewer']!.avatarUrl,
        'https://static-cdn.jtvnw.net/avatar.png',
      );
      expect(
        metadata.badges['channel/subscriber/12']!.imageUrl,
        endsWith('/channel.png'),
      );
      final normalized = normalizeTwitchEvent('chat', {
        'badges': [
          {'set_id': 'subscriber', 'id': '12'},
        ],
      });
      expect(normalized['badges'], 'subscriber');
      expect(twitchBadgeReferences(normalized), [
        (set: 'subscriber', version: '12'),
      ]);
      expect(
        twitchBadgeChannel({'source_broadcaster_user_id': 'source'}, 'channel'),
        'source',
      );
    },
  );

  test(
    'image URLs are provider-scoped HTTPS with no credentials or custom ports',
    () {
      expect(
        twitchProfileImage('https://static-cdn.jtvnw.net/image.png'),
        isNotNull,
      );
      for (final url in [
        'http://static-cdn.jtvnw.net/a',
        'https://127.0.0.1/a',
        'https://user:pass@static-cdn.jtvnw.net/a',
        'https://static-cdn.jtvnw.net:444/a',
        'javascript:alert(1)',
        'https://static-cdn.jtvnw.net.evil.test/a',
      ]) {
        expect(twitchProfileImage(url), isNull);
      }
      expect(
        youtubeChatAvatar({
          'authorDetails': {'profileImageUrl': 'https://yt3.ggpht.com/a'},
        }),
        isNotNull,
      );
      expect(
        youtubeChatAvatar({
          'authorDetails': {'profileImageUrl': 'https://localhost/a'},
        }),
        isNull,
      );
    },
  );

  test(
    'oversized batches fail before HTTP and late results stop after close',
    () async {
      final pending = Completer<RuntimeMap>();
      var requests = 0;
      final source = TwitchChatMetadataSource(
        dataService: data,
        request: (_, _, _, _) async {
          requests++;
          return pending.future;
        },
      );
      await expectLater(source.load({}, {}), throwsArgumentError);
      await expectLater(
        source.load({for (var i = 0; i < 101; i++) '$i'}, {}),
        throwsArgumentError,
      );
      expect(requests, 0);
      final loading = source.load({'viewer'}, {'channel'});
      await source.close();
      pending.complete({'data': []});
      await expectLater(loading, throwsStateError);
      expect(requests, 1);
    },
  );
}
