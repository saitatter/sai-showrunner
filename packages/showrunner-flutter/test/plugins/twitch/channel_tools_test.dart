import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/twitch/actions.dart';
import 'package:showrunner_flutter/runtime/expression.dart';

void main() {
  late DartPluginRegistry registry;
  late List<({String method, String path, RuntimeMap query, RuntimeMap body})>
  calls;
  setUp(() {
    calls = [];
    registry = DartPluginRegistry()
      ..register(
        createTwitchPlugin(
          TwitchTransport.withDefaults(
            (method, path, query, body) async {
              calls.add((method: method, path: path, query: query, body: body));
              return {
                'data': [
                  {
                    'id': 'session',
                    'tags': ['Română', 'Gaming'],
                  },
                ],
              };
            },
            broadcasterId: 'owner',
            moderatorId: 'owner',
          ),
        ),
      );
  });
  tearDown(() => registry.close());

  test('dedicated tag nodes replace / clear only tags', () async {
    expect(await registry.invokeAction('twitch', 'getChannelTags', {}), {
      'tags': ['Română', 'Gaming'],
    });
    expect(calls.last.method, 'GET');
    expect(calls.last.path, '/helix/channels');
    await registry.invokeAction('twitch', 'setChannelTags', {
      'tags': ['Română', 'Gaming'],
    });
    expect(calls.last.method, 'PATCH');
    expect(calls.last.query, {'broadcaster_id': 'owner'});
    expect(calls.last.body, {
      'tags': ['Română', 'Gaming'],
    });
    await registry.invokeAction('twitch', 'setChannelTags', {'tags': []});
    expect(calls.last.body, {'tags': []});
    for (final tags in [
      null,
      ['two words'],
      ['special!'],
      List.filled(11, 'tag'),
      [List.filled(26, 'x').join()],
    ]) {
      await expectLater(
        registry.invokeAction('twitch', 'setChannelTags', {'tags': tags}),
        throwsArgumentError,
      );
    }
    expect(calls, hasLength(3));
  });

  test(
    'clip download query uses authorized editor and up to ten repeated IDs',
    () async {
      await registry.invokeAction('twitch', 'getClipDownloadUrls', {
        'clipIds': ['a', 'b'],
      });
      expect(calls.last.path, '/helix/clips/downloads');
      expect(calls.last.query, {
        'broadcaster_id': 'owner',
        'editor_id': 'owner',
        'clip_id': ['a', 'b'],
      });
      await registry.invokeAction('twitch', 'getClipDownloadUrls', {
        'broadcasterId': 'other',
        'editorId': 'editor',
        'clipIds': ['clip'],
      });
      expect(calls.last.query['editor_id'], 'editor');
      for (final ids in [
        [],
        List.filled(11, 'clip'),
        [42],
        [''],
      ]) {
        await expectLater(
          registry.invokeAction('twitch', 'getClipDownloadUrls', {
            'clipIds': ids,
          }),
          throwsArgumentError,
        );
      }
      expect(calls, hasLength(2));
    },
  );

  test(
    'Guest Star session operations respect broadcaster-only endpoints',
    () async {
      await registry.invokeAction('twitch', 'getGuestStarSession', {});
      expect(calls.last.query, {
        'broadcaster_id': 'owner',
        'moderator_id': 'owner',
      });
      await registry.invokeAction('twitch', 'createGuestStarSession', {});
      expect(calls.last.method, 'POST');
      expect(calls.last.path, '/helix/guest_star/session');
      expect(calls.last.query, {'broadcaster_id': 'owner'});
      await registry.invokeAction('twitch', 'endGuestStarSession', {
        'sessionId': 'session',
      });
      expect(calls.last.method, 'DELETE');
      expect(calls.last.query, {
        'broadcaster_id': 'owner',
        'session_id': 'session',
      });
      await expectLater(
        registry.invokeAction('twitch', 'endGuestStarSession', {}),
        throwsArgumentError,
      );
      expect(calls, hasLength(3));
    },
  );

  test(
    'Guest Star invitations and slots require concrete session / guest IDs',
    () async {
      for (final item in [
        ('getGuestStarInvites', 'invites', 'GET'),
        ('sendGuestStarInvite', 'invites', 'POST'),
        ('deleteGuestStarInvite', 'invites', 'DELETE'),
        ('assignGuestStarSlot', 'slot', 'POST'),
        ('deleteGuestStarSlot', 'slot', 'DELETE'),
      ]) {
        await registry.invokeAction('twitch', item.$1, {
          'sessionId': 'session',
          'guestId': 'guest',
          'slotId': '2',
          'reinvite': true,
        });
        expect(calls.last.method, item.$3);
        expect(calls.last.path, '/helix/guest_star/${item.$2}');
        expect(calls.last.query, {
          'broadcaster_id': 'owner',
          'moderator_id': 'owner',
          'session_id': 'session',
          if (item.$3 != 'GET') 'guest_id': 'guest',
          if (item.$2 == 'slot') 'slot_id': '2',
          if (item.$1 == 'deleteGuestStarSlot') 'should_reinvite_guest': true,
        });
        expect(calls.last.body, isEmpty);
      }
      for (final config in [
        <String, dynamic>{},
        {'sessionId': 'session'},
        {'sessionId': 'session', 'guestId': 'guest'},
        {'sessionId': 'session', 'guestId': 'guest', 'slotId': '0'},
        {
          'sessionId': 'session',
          'guestId': 'guest',
          'slotId': '2',
          'reinvite': 'false',
        },
      ]) {
        await expectLater(
          registry.invokeAction('twitch', 'assignGuestStarSlot', config),
          throwsArgumentError,
        );
      }
      expect(calls, hasLength(5));
    },
  );
}
