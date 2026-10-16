import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/twitch/actions.dart';
import 'package:showrunner_flutter/plugins/twitch/contracts.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/schema/automation.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';

void main() {
  test('a dropped chat message fails the action even with HTTP 200', () async {
    final registry = DartPluginRegistry()
      ..register(
        createTwitchPlugin(
          TwitchTransport(
            (method, path, query, body) async => {
              'data': [
                {
                  'is_sent': false,
                  'drop_reason': {
                    'code': 'msg_rejected',
                    'message': 'Held by moderation',
                  },
                },
              ],
            },
          ),
        ),
      );
    addTearDown(registry.close);
    await expectLater(
      registry.invokeAction('twitch', 'chat', {'message': 'test'}),
      throwsA(
        isA<StateError>().having(
          (e) => '$e',
          'drop reason',
          contains('Held by moderation'),
        ),
      ),
    );
  });
  test(
    'uses documented Helix bodies and query fields for mutation nodes',
    () async {
      final calls = <Map>[];
      final registry = DartPluginRegistry()
        ..register(
          createTwitchPlugin(
            TwitchTransport.withDefaults(
              (method, path, query, body) async {
                calls.add({'path': path, 'query': query, 'body': body});
                return {};
              },
              broadcasterId: 'channel',
              moderatorId: 'owner',
            ),
          ),
        );
      addTearDown(registry.close);
      await registry.invokeAction('twitch', 'timeout', {
        'viewerId': 'test',
        'duration': 30,
        'reason': 'QA',
      });
      expect(calls.last['body'], {
        'data': {'user_id': 'test', 'duration': 30, 'reason': 'QA'},
      });
      await registry.invokeAction('twitch', 'streamMarker', {
        'markerName': 'QA',
      });
      expect(calls.last['query'], isEmpty);
      expect(calls.last['body'], {'user_id': 'channel', 'description': 'QA'});
      await registry.invokeAction('twitch', 'createPrediction', {
        'title': 'QA',
        'outcomes': ['A', 'B'],
        'duration': 30,
      });
      expect(calls.last['query'], isEmpty);
      expect(calls.last['body'], {
        'broadcaster_id': 'channel',
        'title': 'QA',
        'prediction_window': 30,
        'outcomes': [
          {'title': 'A'},
          {'title': 'B'},
        ],
      });
      await registry.invokeAction('twitch', 'createPoll', {
        'title': 'QA',
        'choices': ['A', 'B'],
        'duration': 15,
      });
      expect(calls.last['query'], isEmpty);
      expect(calls.last['body'], {
        'broadcaster_id': 'channel',
        'title': 'QA',
        'duration': 15,
        'choices': [
          {'title': 'A'},
          {'title': 'B'},
        ],
      });
      await registry.invokeAction('twitch', 'runAd', {'duration': 30});
      expect(calls.last['query'], isEmpty);
      expect(calls.last['body'], {'broadcaster_id': 'channel', 'length': 30});
      await registry.invokeAction('twitch', 'createClip', {
        'createAfterDelay': false,
      });
      expect(calls.last['query'], {
        'broadcaster_id': 'channel',
        'has_delay': false,
      });
      expect(calls.last['body'], isEmpty);
    },
  );
  test(
    'configured graph actions use default IDs and retain explicit targets',
    () async {
      final bodies = <Map>[];
      final queries = <Map>[];
      final registry = DartPluginRegistry()
        ..register(
          createTwitchPlugin(
            TwitchTransport.withDefaults(
              (method, path, query, body) async {
                bodies.add(body);
                queries.add(query);
                return {};
              },
              broadcasterId: 'channel',
              moderatorId: 'sender',
            ),
          ),
        );
      addTearDown(registry.close);
      await registry.invokeAction('twitch', 'chat', {'message': 'test'});
      expect(bodies.last, {
        'broadcaster_id': 'channel',
        'sender_id': 'sender',
        'message': 'test',
      });
      await registry.invokeAction('twitch', 'listChannelPointRewards', {});
      expect(queries.last, {'broadcaster_id': 'channel'});
      await registry.invokeAction('twitch', 'chat', {
        'message': 'test',
        'broadcasterId': 'other',
        'moderatorId': 'explicit',
      });
      expect(bodies.last['broadcaster_id'], 'other');
      expect(bodies.last['sender_id'], 'explicit');
    },
  );
  test('decodes core action configurations into typed contracts', () {
    final plugin = createTwitchPlugin(
      TwitchTransport((method, path, query, body) async => const {}),
    );

    final chat = plugin.actions
        .firstWhere((action) => action.actionId.value == 'chat')
        .decodeConfig({'message': 'hello'});
    expect(chat, isA<TwitchChatConfig>());
    expect((chat as TwitchChatConfig).message, 'hello');

    final prediction = plugin.actions
        .firstWhere((action) => action.actionId.value == 'createPrediction')
        .decodeConfig({
          'title': 'Choose',
          'duration': 60,
          'outcomes': ['yes', 'no'],
        });
    expect(prediction, isA<TwitchPredictionConfig>());
    expect((prediction as TwitchPredictionConfig).outcomes, ['yes', 'no']);

    final timeout = plugin.actions
        .firstWhere((action) => action.actionId.value == 'timeout')
        .decodeConfig({'viewerId': 'viewer-1', 'duration': 30});
    expect(timeout, isA<TwitchTimeoutConfig>());
    expect((timeout as TwitchTimeoutConfig).duration, 30);

    final reward = plugin.actions
        .firstWhere(
          (action) => action.actionId.value == 'createChannelPointReward',
        )
        .decodeConfig({
          'name': 'Hydrate',
          'rewardData': {'cost': 250, 'prompt': 'Take a sip'},
        });
    expect(reward, isA<TwitchChannelPointRewardConfig>());
    expect((reward as TwitchChannelPointRewardConfig).title, 'Hydrate');
    expect(reward.cost, 250);

    final group = plugin.actions
        .firstWhere((action) => action.actionId.value == 'addViewerToGroup')
        .decodeConfig({'group': 'moderators', 'viewer': 'viewer-1'});
    expect(group, isA<TwitchViewerGroupConfig>());
    expect((group as TwitchViewerGroupConfig).group, 'moderators');
  });

  test('builds Twitch Helix actions through an injectable transport', () async {
    final requests = <String>[];
    final transport = TwitchTransport((method, path, query, body) async {
      requests.add(
        '$method $path ${body['description'] ?? (body['data'] as Map?)?['user_id'] ?? body['message'] ?? ''}',
      );
      return path == '/helix/clips'
          ? {
              'data': [
                {'id': 'clip-1'},
              ],
            }
          : {};
    });
    final registry = DartPluginRegistry()
      ..register(createTwitchPlugin(transport));
    final context = EvaluationContext(
      contextState: {
        'broadcasterId': 'broadcaster-1',
        'moderatorId': 'moderator-1',
      },
    );

    final clip = await registry.invoke(
      const GraphNode(
        id: 'clip',
        type: 'action',
        x: 0,
        y: 0,
        data: {'plugin': 'twitch', 'action': 'createClip'},
      ),
      context,
      {},
    );
    await registry.invoke(
      const GraphNode(
        id: 'ban',
        type: 'action',
        x: 0,
        y: 0,
        data: {'plugin': 'twitch', 'action': 'ban'},
      ),
      context,
      {'viewerId': 'viewer-1', 'reason': 'test'},
    );
    await registry.invokeAction('twitch', 'runAd', {'duration': 60});
    await registry.invokeAction('twitch', 'snoozeAds', {});
    await registry.invokeAction('twitch', 'createPrediction', {
      'title': 'Choose wisely',
      'duration': 60,
      'outcomes': ['Yes', 'No'],
    });
    await registry.invokeAction('twitch', 'announcement', {
      'message': 'Welcome',
      'color': 'blue',
    });
    await registry.invokeAction('twitch', 'shoutout', {
      'streamer': 'creator-1',
    });
    await registry.invokeAction('twitch', 'setStreamInfo', {
      'title': 'Live now',
      'categoryId': 'game-1',
      'tags': ['live'],
    });
    await registry.invokeAction('twitch', 'createPoll', {
      'title': 'Choose',
      'duration': 30,
      'choices': ['A', 'B'],
    });
    await registry.invokeAction('twitch', 'startRaid', {'target': 'creator-1'});
    await registry.invokeAction('twitch', 'cancelRaid', {});

    expect(clip, {'clipId': 'clip-1'});
    expect(requests, [
      'POST /helix/clips ',
      'POST /helix/moderation/bans viewer-1',
      'POST /helix/channels/commercial ',
      'POST /helix/channels/ads/schedule/snooze ',
      'POST /helix/predictions ',
      'POST /helix/chat/announcements Welcome',
      'POST /helix/chat/shoutouts ',
      'PATCH /helix/channels ',
      'POST /helix/polls ',
      'POST /helix/raids ',
      'DELETE /helix/raids ',
    ]);
  });

  test('declares editor schemas for every Twitch action', () {
    final plugin = createTwitchPlugin(
      TwitchTransport((method, path, query, body) async => const {}),
    );

    expect(plugin.actions, isNotEmpty);
    expect(
      plugin.actions.every((action) => action.configSchema != null),
      isTrue,
    );
    expect(
      plugin.actions
          .firstWhere((action) => action.actionId.value == 'createPrediction')
          .configSchema!
          .fields
          .map((field) => field.key),
      containsAll(<String?>['title', 'duration', 'outcomes']),
    );
  });

  test('filters redemption triggers by the configured reward ID', () {
    final hub = DartPluginEventHub();
    final trigger = createTwitchPlugin(
      TwitchTransport((method, path, query, body) async => const {}),
      eventHub: hub,
    ).triggers.firstWhere((trigger) => trigger.triggerId.value == 'redemption');

    expect(trigger.configSchema?.fields.single.key, 'rewardId');
    expect(
      trigger.matchesRuntime(
        {'rewardId': 'reward-1'},
        {'rewardId': 'reward-1'},
      ),
      isTrue,
    );
    expect(
      trigger.matchesRuntime(
        {'rewardId': 'reward-1'},
        {'rewardId': 'reward-2'},
      ),
      isFalse,
    );
  });

  test(
    'persists viewer group mutations through the resource repository',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'showrunner-twitch-group-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repository = ResourceRepository(directory);
      await repository.save(
        const ResourceData(
          id: 'moderators',
          config: {
            'name': 'Moderators',
            'userIds': ['viewer-2'],
          },
        ),
      );
      final registry = DartPluginRegistry()
        ..register(
          createTwitchPlugin(
            TwitchTransport((method, path, query, body) async => const {}),
            viewerGroupRepository: repository,
          ),
        );

      await registry.invokeAction('twitch', 'addViewerToGroup', {
        'group': 'moderators',
        'viewer': 'viewer-1',
      });
      expect((await repository.load('moderators'))!.config['userIds'], [
        'viewer-1',
        'viewer-2',
      ]);

      await registry.invokeAction('twitch', 'removeViewerFromGroup', {
        'group': 'moderators',
        'viewer': 'viewer-2',
      });
      expect((await repository.load('moderators'))!.config['userIds'], [
        'viewer-1',
      ]);

      await registry.invokeAction('twitch', 'clearViewerGroup', {
        'group': 'moderators',
      });
      expect((await repository.load('moderators'))!.config['userIds'], isEmpty);
    },
  );
}
