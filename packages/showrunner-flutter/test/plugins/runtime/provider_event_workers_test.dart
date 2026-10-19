import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/runtime/provider_event_workers.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  test('does not report stopped workers as running', () async {
    final hub = DartPluginEventHub();
    final providerEvents = ProviderEventRuntime(
      dataService: ShowRunnerDataService(
        Directory('${Directory.systemTemp.path}/provider-worker-status-data'),
      ),
      eventHub: hub,
    );
    providerEvents.twitch = TwitchEventSubWorker(
      accessToken: 'token',
      clientId: 'client',
      broadcasterId: 'broadcaster',
      request: (method, path, query, body) async => <String, dynamic>{},
      eventHub: hub,
    );
    providerEvents.youtube = YouTubeLiveChatWorker(
      request: (method, path, query, body) async => <String, dynamic>{},
      eventHub: hub,
      liveChatId: 'live-chat',
    );

    expect(providerEvents.twitchRunning, isFalse);
    expect(providerEvents.youtubeRunning, isFalse);

    await hub.dispose();
  });

  test('keeps the trigger set for all active profiles', () async {
    final hub = DartPluginEventHub();
    final providerEvents = ProviderEventRuntime(
      dataService: ShowRunnerDataService(
        Directory('${Directory.systemTemp.path}/provider-profile-data'),
      ),
      eventHub: hub,
    );
    var notifications = 0;
    providerEvents.addListener(() => notifications++);

    providerEvents.updateProfileActivity(
      'main',
      active: true,
      triggers: [
        {
          'plugin': 'spellcast',
          'trigger': 'spellHook',
          'config': {'spell': 'local-one'},
        },
      ],
    );
    providerEvents.updateProfileActivity(
      'backup',
      active: true,
      triggers: [
        {
          'plugin': 'spellcast',
          'trigger': 'spellHook',
          'config': {'spell': 'local-two'},
        },
      ],
    );
    expect(providerEvents.activeProfileTriggers, hasLength(2));

    providerEvents.updateProfileActivity('main', active: false);
    expect(providerEvents.activeProfileTriggers.single['config'], {
      'spell': 'local-two',
    });
    expect(notifications, 3);

    await hub.dispose();
  });
}
