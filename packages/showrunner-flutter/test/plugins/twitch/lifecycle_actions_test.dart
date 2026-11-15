import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/twitch/actions.dart';
import 'package:showrunner_flutter/plugins/twitch/event_parser.dart';
import 'package:showrunner_flutter/plugins/twitch/eventsub_subscriptions.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';

void main() {
  late DartPluginRegistry registry;
  late DartPluginEventHub hub;
  late List<({String method, String path, RuntimeMap query, RuntimeMap body})>
  calls;
  setUp(() {
    calls = [];
    hub = DartPluginEventHub();
    registry = DartPluginRegistry()
      ..register(
        createTwitchPlugin(
          TwitchTransport.withDefaults(
            (method, path, query, body) async {
              calls.add((method: method, path: path, query: query, body: body));
              return {
                'data': [
                  {'id': 'result'},
                ],
                'pagination': {'cursor': 'next'},
              };
            },
            broadcasterId: 'owner',
            moderatorId: 'moderator',
          ),
          eventHub: hub,
        ),
      );
  });
  tearDown(() async {
    await registry.close();
    await hub.dispose();
  });

  test(
    'poll / prediction pages return data and cursors without losing IDs',
    () async {
      for (final resource in ['Polls', 'Predictions']) {
        final result = await registry.invokeAction('twitch', 'get$resource', {
          'ids': ['first', 'second'],
          'first': 2,
          'after': 'cursor',
        });
        expect(calls.last.method, 'GET');
        expect(calls.last.path, '/helix/${resource.toLowerCase()}');
        expect(calls.last.query, {
          'broadcaster_id': 'owner',
          'id': ['first', 'second'],
          'first': 2,
          'after': 'cursor',
        });
        expect(calls.last.body, isEmpty);
        expect(result, {
          'data': [
            {'id': 'result'},
          ],
          'pagination': {'cursor': 'next'},
        });
      }
    },
  );

  test(
    'each lifecycle node uses an explicit ID and documented status',
    () async {
      for (final operation in [
        ('terminatePoll', 'polls', 'TERMINATED'),
        ('archivePoll', 'polls', 'ARCHIVED'),
        ('lockPrediction', 'predictions', 'LOCKED'),
        ('resolvePrediction', 'predictions', 'RESOLVED'),
        ('cancelPrediction', 'predictions', 'CANCELED'),
      ]) {
        await registry.invokeAction('twitch', operation.$1, {
          'broadcasterId': 'explicit',
          'id': 'specific',
          'winningOutcomeId': 'winning',
        });
        expect(calls.last.method, 'PATCH');
        expect(calls.last.path, '/helix/${operation.$2}');
        expect(calls.last.query, isEmpty);
        expect(calls.last.body, {
          'broadcaster_id': 'explicit',
          'id': 'specific',
          'status': operation.$3,
          if (operation.$3 == 'RESOLVED') 'winning_outcome_id': 'winning',
        });
      }
    },
  );

  test('invalid lifecycle inputs fail before sending a mutation', () async {
    for (final config in [
      <String, dynamic>{},
      {'id': 'x'},
      {'id': 'x', 'winningOutcomeId': 42},
    ]) {
      await expectLater(
        registry.invokeAction('twitch', 'resolvePrediction', config),
        throwsArgumentError,
      );
    }
    for (final config in [
      {'ids': List.filled(21, 'x')},
      {'first': 0},
      {'first': 21},
      {'first': 1.5},
      {'first': double.nan},
      {
        'ids': [''],
      },
      {'ids': 'x'},
      {'after': 42},
    ]) {
      await expectLater(
        registry.invokeAction('twitch', 'getPolls', config),
        throwsArgumentError,
      );
    }
    expect(calls, isEmpty);
  });

  test('pin / unpin use query parameters and never a JSON body', () async {
    await registry.invokeAction('twitch', 'pinMessage', {
      'messageId': 'message',
      'duration': 30,
    });
    expect(calls.last.method, 'PUT');
    expect(calls.last.path, '/helix/chat/pins');
    expect(calls.last.query, {
      'broadcaster_id': 'owner',
      'moderator_id': 'moderator',
      'message_id': 'message',
      'duration_seconds': 30,
    });
    expect(calls.last.body, isEmpty);
    await registry.invokeAction('twitch', 'pinMessage', {
      'messageId': 'message',
    });
    expect(calls.last.query, isNot(contains('duration_seconds')));
    await registry.invokeAction('twitch', 'unpinMessage', {
      'messageId': 'message',
    });
    expect(calls.last.method, 'DELETE');
    expect(calls.last.query, {
      'broadcaster_id': 'owner',
      'moderator_id': 'moderator',
      'message_id': 'message',
    });
    for (final duration in [29, 1801, 30.5]) {
      await expectLater(
        registry.invokeAction('twitch', 'pinMessage', {
          'messageId': 'message',
          'duration': duration,
        }),
        throwsArgumentError,
      );
    }
    expect(calls, hasLength(3));
  });

  test(
    'role changes never perform implicit demotions or extra requests',
    () async {
      for (final operation in [
        ('addVip', 'channels/vips', 'POST'),
        ('removeVip', 'channels/vips', 'DELETE'),
        ('addModerator', 'moderation/moderators', 'POST'),
        ('removeModerator', 'moderation/moderators', 'DELETE'),
      ]) {
        await registry.invokeAction('twitch', operation.$1, {
          'viewerId': 'viewer',
        });
        expect(calls.last.path, '/helix/${operation.$2}');
        expect(calls.last.method, operation.$3);
        expect(calls.last.query, {
          'broadcaster_id': 'owner',
          'user_id': 'viewer',
        });
        expect(calls.last.body, isEmpty);
      }
      expect(calls, hasLength(4));
    },
  );

  test(
    'warnings and AutoMod decisions preserve actor IDs and private text',
    () async {
      await registry.invokeAction('twitch', 'warnUser', {
        'viewerId': 'viewer',
        'reason': 'Respect the rules',
      });
      expect(calls.last.path, '/helix/moderation/warnings');
      expect(calls.last.query, {
        'broadcaster_id': 'owner',
        'moderator_id': 'moderator',
      });
      expect(calls.last.body, {
        'data': {'user_id': 'viewer', 'reason': 'Respect the rules'},
      });
      for (final operation in [
        ('allowAutoModMessage', 'ALLOW'),
        ('denyAutoModMessage', 'DENY'),
      ]) {
        await registry.invokeAction('twitch', operation.$1, {
          'messageId': 'held',
        });
        expect(calls.last.path, '/helix/moderation/automod/message');
        expect(calls.last.query, isEmpty);
        expect(calls.last.body, {
          'user_id': 'moderator',
          'msg_id': 'held',
          'action': operation.$2,
        });
      }
      await expectLater(
        registry.invokeAction('twitch', 'warnUser', {
          'viewerId': 'viewer',
          'reason': List.filled(501, 'x').join(),
        }),
        throwsArgumentError,
      );
      expect(calls, hasLength(3));
    },
  );

  test(
    'new triggers decode rich lifecycle / moderation data through the registry',
    () async {
      for (final item in [
        ('channel.poll.progress', 'pollProgress'),
        ('channel.prediction.progress', 'predictionProgress'),
        ('automod.message.hold', 'autoModMessageHeld'),
        ('automod.message.update', 'autoModMessageUpdated'),
        ('automod.settings.update', 'autoModSettingsUpdated'),
        ('automod.terms.update', 'autoModTermsUpdated'),
        ('channel.warning.send', 'warningSent'),
        ('channel.warning.acknowledge', 'warningAcknowledged'),
      ]) {
        expect(twitchDomainEventType(item.$1, {}, 'owner'), item.$2);
        final trigger = registry.plugins.single.triggers.firstWhere(
          (t) => t.triggerId.value == item.$2,
        );
        final raw = normalizeTwitchEvent(item.$2, {
          'id': 'lifecycle',
          'user_id': 'viewer',
          'message_id': 'held',
          'moderator_user_id': 'moderator',
          'message': {'text': 'private held text'},
          'reason': 'rules',
          'outcomes': [
            {'id': 'winner', 'channel_points': 42},
          ],
          'choices': [
            {'id': 'choice', 'votes': 4},
          ],
        });
        final pendingEvent = trigger.listenFromRuntime().first;
        hub.emit(item.$2, raw);
        final event = await pendingEvent;
        if (item.$2 == 'pollProgress') {
          expect(event['pollId'], 'lifecycle');
          expect(event['choices'], [
            {'id': 'choice', 'votes': 4},
          ]);
        } else if (item.$2 == 'predictionProgress') {
          expect(event['predictionId'], 'lifecycle');
          expect(event['outcomes'], [
            {'id': 'winner', 'channel_points': 42},
          ]);
        } else {
          expect(event['message'], 'private held text');
          expect(event['moderatorId'], 'moderator');
          expect(event['details'], containsPair('reason', 'rules'));
        }
      }
    },
  );

  test('AutoMod v2 and warnings subscribe with the authorized moderator', () {
    final subscriptions = defaultTwitchEventSubSubscriptions('owner');
    for (final type in [
      'automod.message.hold',
      'automod.message.update',
      'automod.settings.update',
      'automod.terms.update',
      'channel.warning.send',
      'channel.warning.acknowledge',
    ]) {
      final subscription = subscriptions.singleWhere((s) => s.type == type);
      expect(
        subscription.version,
        type.startsWith('automod.message.') ? '2' : '1',
      );
      expect(subscription.condition, {
        'broadcaster_user_id': 'owner',
        'moderator_user_id': 'owner',
      });
    }
  });
}
