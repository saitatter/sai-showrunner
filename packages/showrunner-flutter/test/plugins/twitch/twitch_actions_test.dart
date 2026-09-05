import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/twitch/actions.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/schema/automation.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';

void main() {
  test('builds Twitch Helix actions through an injectable transport', () async {
    final requests = <String>[];
    final transport = TwitchTransport((method, path, query, body) async {
      requests.add(
        '$method $path ${body['comment'] ?? body['user_id'] ?? body['message'] ?? ''}',
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
          .firstWhere((action) => action.actionId == 'createPrediction')
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
    ).triggers.firstWhere((trigger) => trigger.triggerId == 'redemption');

    expect(trigger.configSchema?.fields.single.key, 'rewardId');
    expect(
      trigger.matches?.call({'rewardId': 'reward-1'}, {'rewardId': 'reward-1'}),
      isTrue,
    );
    expect(
      trigger.matches?.call({'rewardId': 'reward-1'}, {'rewardId': 'reward-2'}),
      isFalse,
    );
  });
}
