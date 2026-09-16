import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/youtube/actions.dart';
import 'package:showrunner_flutter/plugins/youtube/contracts.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/schema/automation.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';

void main() {
  test('decodes action and event payloads into typed contracts', () async {
    final eventHub = DartPluginEventHub();
    final plugin = createYouTubePlugin(
      YouTubeTransport((method, path, query, body) async => const {}),
      eventHub: eventHub,
    );

    final message = plugin.actions
        .firstWhere((action) => action.actionId.value == 'sendChatMessage')
        .decodeConfig({'message': 'hello'});
    expect(message, isA<YouTubeSendChatMessageConfig>());
    expect((message as YouTubeSendChatMessageConfig).message, 'hello');

    final ban = plugin.actions
        .firstWhere((action) => action.actionId.value == 'banUser')
        .decodeConfig({'channelId': 'channel-1', 'banDurationSeconds': 30});
    expect(ban, isA<YouTubeBanUserConfig>());
    expect((ban as YouTubeBanUserConfig).durationSeconds, 30);

    final trigger = plugin.triggers.firstWhere(
      (item) => item.triggerId.value == 'chatMessage',
    );
    final event = trigger.listen();
    final expectation = expectLater(
      event,
      emits(isA<YouTubeChatMessageEvent>()),
    );
    eventHub.emit('chatMessage', {
      'viewerId': 'viewer-1',
      'viewerName': 'Ada',
      'message': 'hello',
      'messageId': 'message-1',
      'isModerator': false,
      'isMember': true,
      'isOwner': false,
    });
    await expectation;
    await eventHub.dispose();
  });

  test(
    'builds authorized YouTube API actions through an injectable transport',
    () async {
      final requests = <String>[];
      final transport = YouTubeTransport((method, path, query, body) async {
        requests.add('$method $path ${query['id'] ?? query['part']}');
        return {};
      });
      final registry = DartPluginRegistry()
        ..register(createYouTubePlugin(transport));

      await registry.invoke(
        const GraphNode(
          id: 'chat',
          type: 'action',
          x: 0,
          y: 0,
          data: {'plugin': 'youtube', 'action': 'sendChatMessage'},
        ),
        EvaluationContext(contextState: {'liveChatId': 'chat-1'}),
        {'message': 'hello'},
      );
      await registry.invoke(
        const GraphNode(
          id: 'ban',
          type: 'action',
          x: 0,
          y: 0,
          data: {'plugin': 'youtube', 'action': 'banUser'},
        ),
        EvaluationContext(contextState: {'liveChatId': 'chat-1'}),
        {'channelId': 'channel-1', 'banDurationSeconds': 30},
      );

      expect(requests, [
        'POST /youtube/v3/liveChat/messages snippet',
        'POST /youtube/v3/liveChat/bans snippet',
      ]);
    },
  );

  test('declares editor schemas for every YouTube action', () {
    final plugin = createYouTubePlugin(
      YouTubeTransport((method, path, query, body) async => const {}),
    );

    expect(plugin.actions, isNotEmpty);
    expect(
      plugin.actions.every((action) => action.configSchema != null),
      isTrue,
    );
  });
}
