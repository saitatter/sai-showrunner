import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/secret_settings_store.dart';
import 'package:showrunner_flutter/plugins/runtime/provider_event_workers.dart';
import 'package:showrunner_flutter/plugins/runtime/provider_operation_policy.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  late ShowRunnerDataService data;
  late DartPluginEventHub hub;
  setUp(() async {
    final root = await Directory.systemTemp.createTemp('provider-runtime-');
    addTearDown(() => root.delete(recursive: true));
    data = ShowRunnerDataService(
      root,
      secretSettings: SecretSettingsStore(
        directory: Directory('${root.path}/secrets'),
        encrypt: (bytes) async => bytes,
        decrypt: (bytes) async => bytes,
      ),
    );
    hub = DartPluginEventHub();
    addTearDown(hub.dispose);
    await data.savePluginSettings('youtube', {
      'accessToken': 'fixture',
      'liveChatId': 'saved-chat',
    });
    await data.savePluginSettings('twitch', {
      'accessToken': 'fixture',
      'clientId': 'client',
      'broadcasterId': 'channel',
    });
  });

  test('Twitch disconnect does not cancel YouTube discovery', () async {
    final entered = Completer<void>();
    final response = Completer<Map<String, dynamic>>();
    final runtime = ProviderEventRuntime(
      dataService: data,
      eventHub: hub,
      youtubeRequestFactory: ({required accessToken, required scope}) =>
          (method, path, query, body) {
            entered.complete();
            return response.future;
          },
    );
    addTearDown(runtime.dispose);
    final discovery = runtime.discoverYouTubeBroadcast();
    await entered.future;
    await runtime.stopTwitch();
    response.complete({
      'items': [
        {
          'id': 'broadcast',
          'snippet': {'liveChatId': 'chat'},
        },
      ],
    });
    expect((await discovery)['id'], 'broadcast');
    await runtime.stop();
  });

  test('concurrent chat starts keep only the latest selection', () async {
    final runtime = ProviderEventRuntime(
      dataService: data,
      eventHub: hub,
      youtubeRequestFactory: ({required accessToken, required scope}) =>
          (method, path, query, body) async => {'items': []},
    );
    addTearDown(runtime.dispose);
    await Future.wait([
      runtime.startYouTubeChat(liveChatId: 'old'),
      runtime.startYouTubeChat(liveChatId: 'latest'),
    ]);
    expect(runtime.youtube!.liveChatId, 'latest');
    await runtime.stop();
  });

  test('disconnect invalidates both starts before settings return', () async {
    var connections = 0;
    final runtime = ProviderEventRuntime(
      dataService: data,
      eventHub: hub,
      twitchSocketFactory: (_) async {
        connections++;
        throw StateError('unexpected socket');
      },
      youtubeRequestFactory: ({required accessToken, required scope}) {
        connections++;
        return (method, path, query, body) async => {};
      },
    );
    addTearDown(runtime.dispose);
    final starting = runtime.start();
    await runtime.stop();
    await starting;
    expect(connections, 0);
    expect(runtime.twitch, isNull);
    expect(runtime.youtube, isNull);
  });

  test(
    'individual starts cannot resurrect after immediate disconnect',
    () async {
      final runtime = ProviderEventRuntime(dataService: data, eventHub: hub);
      addTearDown(runtime.dispose);
      final twitch = runtime.startTwitch();
      final youtube = runtime.startYouTubeChat();
      await Future.wait([runtime.stopTwitch(), runtime.stopYouTubeChat()]);
      await Future.wait([twitch, youtube]);
      expect(runtime.twitch, isNull);
      expect(runtime.youtube, isNull);
    },
  );

  test('late Twitch socket is closed without creating subscriptions', () async {
    final entered = Completer<void>();
    final connection = Completer<EventSubSocket>();
    var requests = 0;
    late ProviderOperationScope owned;
    final runtime = ProviderEventRuntime(
      dataService: data,
      eventHub: hub,
      twitchSocketFactory: (_) {
        entered.complete();
        return connection.future;
      },
      twitchRequestFactory:
          ({required accessToken, required clientId, required scope}) {
            owned = scope;
            // The test keeps this request local; no Helix call is permitted.
            return (method, path, query, body) async {
              requests++;
              return {};
            };
          },
    );
    addTearDown(runtime.dispose);
    final starting = runtime.startTwitch();
    await entered.future;
    await runtime.stopTwitch();
    final socket = _Socket();
    connection.complete(socket);
    await starting;
    expect(socket.closed, isTrue);
    expect(requests, 0);
    expect(runtime.twitch, isNull);
    expect(owned.isClosed, isTrue);
  });

  test(
    'late broadcast discovery cannot overwrite state after disconnect',
    () async {
      final entered = Completer<void>();
      final response = Completer<Map<String, dynamic>>();
      late ProviderOperationScope owned;
      var calls = 0;
      final runtime = ProviderEventRuntime(
        dataService: data,
        eventHub: hub,
        youtubeRequestFactory: ({required accessToken, required scope}) {
          owned = scope;
          return (method, path, query, body) {
            calls++;
            entered.complete();
            return response.future;
          };
        },
      );
      addTearDown(runtime.dispose);
      final discovering = expectLater(
        runtime.discoverYouTubeBroadcast(),
        throwsStateError,
      );
      await entered.future;
      await runtime.stopYouTubeChat();
      expect(owned.isClosed, isTrue);
      response.complete({
        'items': [
          {
            'id': 'late',
            'snippet': {'liveChatId': 'late-chat'},
          },
        ],
      });
      await discovering;
      expect(runtime.youtubeBroadcast, isNull);
      expect(calls, 1);
    },
  );

  test(
    'concurrent discovery shares credentials and scope; restart uses new token',
    () async {
      var factories = 0;
      final tokens = <String>[];
      final scopes = <ProviderOperationScope>[];
      final runtime = ProviderEventRuntime(
        dataService: data,
        eventHub: hub,
        youtubeRequestFactory: ({required accessToken, required scope}) {
          factories++;
          tokens.add(accessToken);
          scopes.add(scope);
          return (method, path, query, body) async => {
            'items': [
              {
                'id': 'broadcast',
                'snippet': {'title': 'Fixture', 'liveChatId': 'chat'},
              },
            ],
          };
        },
      );
      addTearDown(runtime.dispose);
      await Future.wait([
        runtime.discoverYouTubeBroadcast(),
        runtime.discoverYouTubeBroadcast(),
      ]);
      expect(factories, 1);
      await runtime.stopYouTubeChat();
      await data.updatePluginSetting('youtube', 'accessToken', 'rotated');
      await runtime.discoverYouTubeBroadcast();
      expect(tokens, ['fixture', 'rotated']);
      expect(scopes.first.isClosed, isTrue);
      expect(scopes.last.isClosed, isFalse);
      await runtime.stop();
      expect(scopes.last.isClosed, isTrue);
    },
  );

  test(
    'YouTube explicit then cached chat selection precedes saved setting',
    () async {
      final scopes = <ProviderOperationScope>[];
      final runtime = ProviderEventRuntime(
        dataService: data,
        eventHub: hub,
        youtubeRequestFactory: ({required accessToken, required scope}) {
          scopes.add(scope);
          return (method, path, query, body) async => {'items': []};
        },
      );
      addTearDown(runtime.dispose);
      await runtime.startYouTubeChat(liveChatId: 'explicit');
      expect(runtime.youtube!.liveChatId, 'explicit');
      final first = runtime.youtube;
      await runtime.stopYouTubeChat();
      await runtime.startYouTubeChat();
      expect(runtime.youtube!.liveChatId, 'explicit');
      expect(identical(first, runtime.youtube), isFalse);
      expect(scopes.first.isClosed, isTrue);
      await runtime.stop();
      await runtime.startYouTubeChat();
      expect(runtime.youtube!.liveChatId, 'saved-chat');
      await runtime.stop();
    },
  );

  test(
    'disposing after disconnect prevents late notifications and further starts',
    () async {
      final runtime = ProviderEventRuntime(dataService: data, eventHub: hub);
      final starting = runtime.startYouTubeChat();
      await runtime.stop();
      runtime.dispose();
      await starting;
      await expectLater(runtime.startTwitch(), throwsStateError);
      expect(() => runtime.simulateYouTubeChatMessage(), throwsStateError);
    },
  );
}

final class _Socket implements EventSubSocket {
  bool closed = false;
  @override
  Stream<dynamic> get messages => const Stream.empty();
  @override
  Future<void> close([int? code, String? reason]) async {
    closed = true;
  }
}
