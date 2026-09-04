import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/moderation/runtime.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  test('moderation test events persist processed message count', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-moderation-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final service = ModerationService(
      dataService: ShowRunnerDataService(directory),
      request: (method, path, query, body) async => const <String, dynamic>{},
    );
    await service.saveSettings(const ModerationSettings(enabled: true));

    final first = await service.sendTestMessage();
    final second = await service.sendTestMessage();

    expect(first.processedMessages, 1);
    expect(second.processedMessages, 2);
    expect(service.status.processedMessages, 2);
  });

  test('moderation action returns a normalized decision result', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-moderation-action-',
    );
    addTearDown(() => directory.delete(recursive: true));
    RuntimeMap? requestBody;
    final service = ModerationService(
      dataService: ShowRunnerDataService(directory),
      request: (method, path, query, body) async {
        requestBody = Map<String, dynamic>.from(body as Map);
        return {
          'moderation': {
            'verdict': 'allow',
            'confidence': 0.98,
            'category': 'safe',
            'reason': 'clean',
          },
        };
      },
    );
    await service.saveSettings(const ModerationSettings(enabled: true));

    final result = await service.moderateChatMessage({
      'platform': 'twitch',
      'viewerId': 'viewer-1',
      'viewerName': 'Viewer',
      'message': 'hello',
      'badges': 'moderator, vip',
      'isModerator': true,
    });

    expect(requestBody?['deliveryMode'], 'decisionOnly');
    expect(requestBody?['actor']['badges'], ['moderator', 'vip']);
    expect(result['verdict'], 'allow');
    expect(result['approved'], true);
    expect(result['blocked'], false);
    expect(result['backendError'], false);
  });
}
