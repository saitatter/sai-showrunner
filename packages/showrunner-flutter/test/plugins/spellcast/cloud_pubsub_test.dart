import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/spellcast/cloud_pubsub.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  late Directory directory;
  late ShowRunnerDataService dataService;
  late DartPluginEventHub eventHub;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('showrunner-cloud-');
    dataService = ShowRunnerDataService(directory);
    await dataService.savePluginSettings('twitch', {'accessToken': 'token'});
    eventHub = DartPluginEventHub();
  });

  tearDown(() async {
    await eventHub.dispose();
    await directory.delete(recursive: true);
  });

  test('maps active profile trigger resources to remote spell IDs', () {
    final spells = [
      ResourceData(id: 'local-one', config: {'spellId': 'remote-one'}),
      ResourceData(id: 'local-two', config: {'spellId': 'remote-two'}),
    ];
    expect(
      resolveActiveSpellcastIds([
        {
          'plugin': 'spellcast',
          'trigger': 'spellHook',
          'config': {'spell': 'local-one'},
        },
        {
          'plugin': 'spellcast',
          'trigger': 'spellHook',
          'config': {'spell': 'local-one'},
        },
        {
          'plugin': 'twitch',
          'trigger': 'chat',
          'config': {'spell': 'local-two'},
        },
        {
          'plugin': 'spellcast',
          'trigger': 'spellHook',
          'config': {'spell': 'missing'},
        },
      ], spells),
      ['remote-one'],
    );
  });

  test(
    'connects, forwards Spellcast events, and clears active spells',
    () async {
      final socket = _FakeCloudPubSubSocket();
      final events = <RuntimeMap>[];
      final subscription = eventHub.stream('spellcast').listen(events.add);
      final controller = SpellcastCloudPubSubController(
        dataService: dataService,
        eventHub: eventHub,
        negotiator: (token) async {
          expect(token, 'token');
          return 'wss://cloud.example.test/client';
        },
        socketFactory: (uri) async {
          expect(uri.host, 'cloud.example.test');
          return socket;
        },
      );

      await controller.start(activeSpellIds: ['spell-1', 'spell-1', '']);
      expect(controller.isConnected, isTrue);
      expect(controller.activeSpellIds, ['spell-1']);
      expect(_eventData(socket.sent).single, {
        'spells': ['spell-1'],
      });

      socket.messagesController.add(
        jsonEncode({
          'type': 'message',
          'dataType': 'json',
          'data': {
            'plugin': 'spellcast',
            'event': 'spellHook',
            'context': {
              'buttonId': 'spell-1',
              'userId': 'viewer-1',
              'bits': 100,
            },
          },
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, [
        {
          'buttonId': 'spell-1',
          'userId': 'viewer-1',
          'bits': 100,
          'spell': 'spell-1',
          'spellId': 'spell-1',
        },
      ]);

      socket.messagesController.add(
        jsonEncode({
          'type': 'message',
          'data': {'plugin': 'spellcast', 'event': 'reinit', 'context': {}},
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(_eventData(socket.sent).last, {
        'spells': ['spell-1'],
      });

      await controller.setActiveSpellIds(const []);
      expect(_eventData(socket.sent).last, {'spells': <String>[]});
      await controller.stop();
      expect(socket.closed, isTrue);
      expect(_eventData(socket.sent).last, {'spells': <String>[]});
      await subscription.cancel();
      controller.dispose();
    },
  );

  test('reports missing credentials without opening a socket', () async {
    final emptyDirectory = await Directory.systemTemp.createTemp(
      'showrunner-cloud-empty-',
    );
    addTearDown(() => emptyDirectory.delete(recursive: true));
    final controller = SpellcastCloudPubSubController(
      dataService: ShowRunnerDataService(emptyDirectory),
      eventHub: eventHub,
      negotiator: (_) async => 'wss://unused.example.test',
      socketFactory: (_) async => _FakeCloudPubSubSocket(),
    );

    await controller.start();
    expect(controller.isConnected, isFalse);
    expect(controller.lastError, isA<StateError>());
    await controller.stop();
    controller.dispose();
  });
}

class _FakeCloudPubSubSocket implements CloudPubSubSocket {
  final messagesController = StreamController<dynamic>.broadcast();
  final sent = <String>[];
  bool closed = false;

  @override
  Stream<dynamic> get messages => messagesController.stream;

  @override
  void add(String message) => sent.add(message);

  @override
  Future<void> close() async {
    closed = true;
    await messagesController.close();
  }
}

List<dynamic> _eventData(List<String> messages) => messages
    .map(jsonDecode)
    .whereType<Map>()
    .map((message) => message['data'])
    .toList();
