import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/youtube/actions.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/schema/automation.dart';

void main() {
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
}
