import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/twitch/actions.dart';
import 'package:showrunner_flutter/plugins/twitch/chat_account_router.dart';
import 'package:showrunner_flutter/plugins/twitch/contracts.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/schema/resource.dart';

void main() {
  test(
    'bot and broadcaster use separate grants with credential-owned sender IDs',
    () async {
      final calls = <String>[];
      final bodies = <RuntimeMap>[];
      final router = TwitchChatAccountRouter(
        broadcasterId: 'channel',
        channelRequest: (method, path, query, body) async {
          calls.add('channel');
          bodies.add(body);
          return {};
        },
        loadBot: () async => const ResourceData(
          id: 'bot',
          config: {'accessToken': 'bot-fixture-token', 'twitchId': 'bot-id'},
        ),
        botRequest: (token) {
          expect(token, 'bot-fixture-token');
          return (method, path, query, body) async {
            calls.add('bot');
            bodies.add(body);
            return {};
          };
        },
      );
      final transport = TwitchTransport.withDefaults(
        (method, path, query, body) async => {},
        broadcasterId: 'channel',
        moderatorId: 'channel',
        chatSender: router.send,
      );
      final plugin = createTwitchPlugin(transport);
      final action = plugin.actions.firstWhere(
        (a) => a.actionId.value == 'chat',
      );
      final context = EvaluationContext();
      await action.invokeFromRuntime({
        'message': 'text',
        'moderatorId': 'spoofed',
      }, context);
      await action.invokeFromRuntime({
        'account': 'bot',
        'message': 'text',
        'moderatorId': 'spoofed',
      }, context);
      expect(calls, ['channel', 'bot']);
      expect(bodies[0]['sender_id'], 'channel');
      expect(bodies[1]['sender_id'], 'bot-id');
      expect(bodies[1]['broadcaster_id'], 'channel');
      expect(bodies.toString(), isNot(contains('bot-fixture-token')));
      expect(
        () => action.decodeConfig({'account': 'unknown'}),
        throwsFormatException,
      );
    },
  );

  test(
    'missing or expired bot never falls back to the channel credential',
    () async {
      var requests = 0;
      for (final bot in [
        null,
        const ResourceData(id: 'bot', config: {}),
        const ResourceData(
          id: 'bot',
          config: {
            'accessToken': 'token',
            'twitchId': 'id',
            'expiresAt': '2000-01-01T00:00:00Z',
          },
        ),
      ]) {
        final router = TwitchChatAccountRouter(
          broadcasterId: 'channel',
          loadBot: () async => bot,
          channelRequest: (_, _, _, _) async {
            requests++;
            return {};
          },
          botRequest: (_) => (_, _, _, _) async {
            requests++;
            return {};
          },
        );
        await expectLater(
          router.send(TwitchChatAccount.bot, {'message': 'text'}),
          throwsStateError,
        );
      }
      expect(requests, 0);
    },
  );
}
