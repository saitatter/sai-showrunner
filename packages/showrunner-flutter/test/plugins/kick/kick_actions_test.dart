import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/kick/actions.dart';
import 'package:showrunner_flutter/plugins/kick/event_worker.dart';
import 'package:showrunner_flutter/runtime/expression.dart';

void main() {
  test(
    'action contracts reach the correct endpoint with validated bodies',
    () async {
      final calls = <RuntimeMap>[];
      var sent = true;
      final plugin = createKickPlugin(
        KickTransport((method, path, query, body) async {
          calls.add({
            'method': method,
            'path': path,
            'query': query,
            'body': body,
          });
          return path == '/public/v1/chat'
              ? {
                  'data': {'is_sent': sent, 'message_id': 'new-message'},
                }
              : {};
        }, readBroadcasterId: () async => '7'),
      );
      Future<Object?> invoke(String id, RuntimeMap config) => plugin.actions
          .singleWhere((action) => action.actionId.value == id)
          .invokeFromRuntime(config, EvaluationContext());
      expect(await invoke('sendChatMessage', {'message': 'Hello'}), {
        'messageId': 'new-message',
      });
      expect(calls.last['body'], {
        'content': 'Hello',
        'type': 'user',
        'broadcaster_user_id': 7,
      });
      await invoke('sendChatMessage', {'message': 'Bot', 'account': 'bot'});
      expect(calls.last['body'], {'content': 'Bot', 'type': 'bot'});
      await invoke('deleteMessage', {'messageId': 'message-id'});
      expect(calls.last, {
        'method': 'DELETE',
        'path': '/public/v1/chat/message-id',
        'query': {},
        'body': null,
      });
      await invoke('banUser', {'userId': '8'});
      expect(calls.last['body'], {'broadcaster_user_id': 7, 'user_id': 8});
      await invoke('timeoutUser', {'userId': '8', 'durationMinutes': 1.0});
      expect(calls.last['body'], {
        'broadcaster_user_id': 7,
        'user_id': 8,
        'duration': 1,
      });
      await invoke('unbanUser', {'userId': '8'});
      expect(calls.last, {
        'method': 'DELETE',
        'path': '/public/v1/moderation/bans',
        'query': {},
        'body': {'broadcaster_user_id': 7, 'user_id': 8},
      });
      final count = calls.length;
      await expectLater(
        invoke('deleteMessage', {'messageId': '../settings'}),
        throwsArgumentError,
      );
      await expectLater(
        invoke('timeoutUser', {'userId': true, 'durationMinutes': 1}),
        throwsArgumentError,
      );
      expect(calls, hasLength(count));
      sent = false;
      await expectLater(
        invoke('sendChatMessage', {'message': 'Hello'}),
        throwsStateError,
      );
    },
  );

  test(
    'worker reuses existing subscriptions and removes only its own',
    () async {
      final calls = <RuntimeMap>[];
      final worker = KickEventWorker(
        broadcasterId: 7,
        publicWebhookUrl: 'https://chat.example.test/kick/webhook',
        port: 0,
        loadPublicKey: () async =>
            throw StateError('Not needed before delivery'),
        onEvent: (_) {},
        request: (method, path, query, body) async {
          calls.add({
            'method': method,
            'path': path,
            'query': query,
            'body': body,
          });
          if (path == '/public/v1/users') {
            return {
              'data': [
                {'user_id': 7},
              ],
            };
          }
          if (method == 'GET') {
            return {
              'data': [
                {
                  'id': 'existing-chat',
                  'event': 'chat.message.sent',
                  'version': 1,
                  'method': 'webhook',
                  'broadcaster_user_id': 7,
                },
                {
                  'id': 'foreign',
                  'event': 'moderation.banned',
                  'version': 1,
                  'method': 'webhook',
                  'broadcaster_user_id': 99,
                },
              ],
            };
          }
          if (method == 'POST') {
            return {
              'data': [
                {
                  'subscription_id': 'created-ban',
                  'name': 'moderation.banned',
                  'version': 1,
                },
              ],
            };
          }
          return {};
        },
      );
      addTearDown(worker.stop);
      await Future.wait([worker.start(), worker.start()]);
      expect(worker.state, 'listening');
      expect(calls.where((call) => call['method'] == 'POST').single['body'], {
        'method': 'webhook',
        'events': [
          {'name': 'moderation.banned', 'version': 1},
        ],
      });
      await worker.stop();
      expect(worker.state, 'stopped');
      expect(
        calls.where((call) => call['method'] == 'DELETE').single['query'],
        {
          'id': ['created-ban'],
        },
      );
      await expectLater(worker.start(), throwsStateError);
    },
  );

  test(
    'worker refuses another account before binding or subscribing',
    () async {
      var requests = 0;
      final worker = KickEventWorker(
        broadcasterId: 7,
        publicWebhookUrl: 'https://chat.example.test/kick/webhook',
        port: 0,
        loadPublicKey: () async => '',
        onEvent: (_) {},
        request: (_, _, _, _) async {
          requests++;
          return {
            'data': [
              {'user_id': 99},
            ],
          };
        },
      );
      addTearDown(worker.stop);
      await expectLater(worker.start(), throwsStateError);
      expect(worker.state, 'error');
      expect(requests, 1);
    },
  );

  test(
    'stop while subscription creation is pending cleans late owned IDs',
    () async {
      final created = Completer<RuntimeMap>();
      final creating = Completer<void>();
      final removed = <Object?>[];
      final worker = KickEventWorker(
        broadcasterId: 7,
        publicWebhookUrl: 'https://chat.example.test/kick/webhook',
        port: 0,
        loadPublicKey: () async => '',
        onEvent: (_) => fail('Stopped worker published an event'),
        request: (method, path, query, body) async {
          if (path == '/public/v1/users') {
            return {
              'data': [
                {'user_id': 7},
              ],
            };
          }
          if (method == 'GET') return {'data': []};
          if (method == 'POST') {
            creating.complete();
            return created.future;
          }
          removed.add(query['id']);
          return {};
        },
      );
      addTearDown(worker.stop);
      final starting = expectLater(worker.start(), throwsStateError);
      await creating.future;
      final stopping = worker.stop();
      created.complete({
        'data': [
          {
            'subscription_id': 'late-chat',
            'name': 'chat.message.sent',
            'version': 1,
          },
          {
            'subscription_id': 'late-ban',
            'name': 'moderation.banned',
            'version': 1,
          },
        ],
      });
      await starting;
      await stopping;
      expect(removed, [
        ['late-chat', 'late-ban'],
      ]);
      expect(worker.state, 'stopped');
    },
  );

  test(
    'partial subscriptions are cleaned without reporting a healthy listener',
    () async {
      final removed = <Object?>[];
      final worker = KickEventWorker(
        broadcasterId: 7,
        publicWebhookUrl: 'https://chat.example.test/kick/webhook',
        port: 0,
        loadPublicKey: () async => '',
        onEvent: (_) {},
        request: (method, path, query, body) async {
          if (path == '/public/v1/users') {
            return {
              'data': [
                {'user_id': 7},
              ],
            };
          }
          if (method == 'GET') return {'data': []};
          if (method == 'POST') {
            return {
              'data': [
                {
                  'subscription_id': 'created-chat',
                  'name': 'chat.message.sent',
                  'version': 1,
                },
                {'error': 'denied', 'name': 'moderation.banned', 'version': 1},
              ],
            };
          }
          removed.add(query['id']);
          return {};
        },
      );
      addTearDown(worker.stop);
      await expectLater(worker.start(), throwsStateError);
      expect(worker.state, 'error');
      expect(removed, [
        ['created-chat'],
      ]);
    },
  );
}
