import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/twitch/channel_runtime.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  test('loads account, channel, and live stream information', () async {
    final directory = await Directory.systemTemp.createTemp('twitch-channel-');
    addTearDown(() => directory.delete(recursive: true));
    final dataService = ShowRunnerDataService(directory);
    await dataService.savePluginSettings('twitch', {
      'accessToken': 'token',
      'clientId': 'client',
      'broadcasterId': 'broadcaster-1',
    });
    final requests = <String>[];
    final service = TwitchChannelInfoService(
      dataService: dataService,
      request: (method, path, query, body) async {
        requests.add('$method $path');
        return switch (path) {
          '/helix/users' => {
            'data': [
              {
                'display_name': 'Streamer',
                'profile_image_url': 'https://cdn.example/avatar.png',
                'view_count': 1234,
              },
            ],
          },
          '/helix/channels' => {
            'data': [
              {
                'title': 'Live from Flutter',
                'game_id': 'game-1',
                'game_name': 'Testing',
                'tags': ['Dart', 'Flutter'],
              },
            ],
          },
          '/helix/streams' => {
            'data': [
              {
                'type': 'live',
                'viewer_count': 42,
                'started_at': '2026-09-05T10:00:00Z',
              },
            ],
          },
          _ => <String, dynamic>{},
        };
      },
    );

    final snapshot = await service.load();

    expect(requests, [
      'GET /helix/users',
      'GET /helix/channels',
      'GET /helix/streams',
    ]);
    expect(snapshot.broadcasterName, 'Streamer');
    expect(snapshot.channelTitle, 'Live from Flutter');
    expect(snapshot.categoryId, 'game-1');
    expect(snapshot.tags, ['Dart', 'Flutter']);
    expect(snapshot.isLive, isTrue);
    expect(snapshot.viewerCount, 42);
    expect(snapshot.viewCount, 1234);
  });

  test('rejects incomplete Twitch credentials before fetching', () async {
    final directory = await Directory.systemTemp.createTemp('twitch-channel-');
    addTearDown(() => directory.delete(recursive: true));
    var called = false;
    final service = TwitchChannelInfoService(
      dataService: ShowRunnerDataService(directory),
      request: (method, path, query, body) async {
        called = true;
        return <String, dynamic>{};
      },
    );

    await expectLater(service.load(), throwsStateError);
    expect(called, isFalse);
  });
}
