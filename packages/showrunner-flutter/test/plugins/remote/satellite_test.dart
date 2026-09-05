import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/remote/satellite.dart';
import 'package:showrunner_flutter/plugins/spellcast/cloud_pubsub.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  test(
    'publishes satellite signaling events and receives matching responses',
    () async {
      final directory = await createTemporaryDirectory('satellite-signaling-');
      addTearDown(() => directory.delete(recursive: true));
      final dataService = ShowRunnerDataService(directory);
      await dataService.savePluginSettings('twitch', {'accessToken': 'token'});
      final socket = _FakeCloudPubSubSocket();
      final signaling = SatelliteSignalingController(
        dataService: dataService,
        negotiator: (token) async {
          expect(token, 'token');
          return 'wss://cloud.example.test/client';
        },
        socketFactory: (uri) async {
          expect(uri.host, 'cloud.example.test');
          return socket;
        },
      );
      final messages = <SatelliteSignalingMessage>[];
      final subscription = signaling.messages.listen(messages.add);

      await signaling.start();
      await signaling.send('satelliteConnectionRequest', {'dashId': 'dash-1'});
      expect(jsonDecode(socket.sent.single), {
        'type': 'event',
        'event': 'satellite_satelliteConnectionRequest',
        'dataType': 'json',
        'data': {'dashId': 'dash-1'},
      });

      socket.messagesController.add(
        jsonEncode({
          'type': 'message',
          'dataType': 'json',
          'data': {
            'plugin': 'satellite',
            'event': 'satelliteConnectionResponse',
            'context': {
              'satelliteId': 'satellite-1',
              'sdp': {'sdp': 'answer', 'type': 'answer'},
            },
          },
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(messages.single.event, 'satelliteConnectionResponse');
      expect(messages.single.data['satelliteId'], 'satellite-1');

      await subscription.cancel();
      signaling.dispose();
    },
  );

  test(
    'negotiates a dashboard, handles config/state, slots, and widget RPC',
    () async {
      final directory = await createTemporaryDirectory('satellite-connection-');
      addTearDown(() => directory.delete(recursive: true));
      final dataService = ShowRunnerDataService(directory);
      await dataService.savePluginSettings('twitch', {'accessToken': 'token'});
      final socket = _FakeCloudPubSubSocket();
      final signaling = SatelliteSignalingController(
        dataService: dataService,
        negotiator: (_) async => 'wss://cloud.example.test/client',
        socketFactory: (_) async => socket,
      );
      await signaling.start();
      final peer = _FakePeerConnection();
      final connection = RemoteSatelliteConnection(
        id: 'connection-1',
        config: const SatelliteConnectionConfig(
          satelliteService: 'twitch',
          satelliteId: 'satellite-1',
          showRunnerService: 'twitch',
          showRunnerId: 'owner-1',
          dashboardId: 'dash-1',
        ),
        signaling: signaling,
        peerFactory: (_) async => peer,
        resourceRpc: (slot, method, args) async {
          expect(slot.resourceId, 'light-1');
          expect(method, 'setLightState');
          expect(args, ['#ffffff', true, 0.2]);
          return {'lightOn': true};
        },
      );

      await connection.start();
      final request = jsonDecode(socket.sent.single) as Map;
      expect(request['event'], 'satellite_satelliteConnectionRequest');
      expect((request['data'] as Map)['ShowRunnerId'], 'owner-1');

      peer.emitPeerState(SatellitePeerState.connected);
      peer.channel.emitState(SatelliteChannelState.open);
      expect(connection.state, SatelliteConnectionState.connected);

      peer.channel.emitMessage(
        jsonEncode({
          'requestId': 'config-1',
          'name': 'dashboard_setConfig',
          'args': [
            {
              'name': 'Studio dashboard',
              'pages': [
                {
                  'id': 'page-1',
                  'name': 'Controls',
                  'sections': [
                    {
                      'id': 'section-1',
                      'name': 'Main',
                      'columns': 4,
                      'widgets': [
                        {
                          'id': 'widget-1',
                          'plugin': 'remote',
                          'widget': 'button',
                          'size': {'width': 2, 'height': 1},
                          'config': {'displayName': 'Start'},
                        },
                      ],
                    },
                  ],
                },
              ],
              'resourceSlots': [
                {'id': 'slot-1', 'name': 'Light', 'slotType': 'Light'},
              ],
            },
          ],
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(connection.dashboard!.name, 'Studio dashboard');
      expect(
        connection.dashboard!.pages.single.sections.single.widgets.single.width,
        2,
      );
      expect(connection.slots.single.resourceType, 'Light');
      expect(jsonDecode(peer.channel.sent.single)['responseId'], 'config-1');

      peer.channel.emitMessage(
        jsonEncode({
          'requestId': 'state-1',
          'name': 'dashboard_stateUpdate',
          'args': ['twitch', 'connection', 'running'],
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(connection.states['twitch']!['connection'], 'running');

      final rpcFuture = connection.callWidgetRpc('widget-1', 'pressbutton', [
        'Start',
      ]);
      await Future<void>.delayed(Duration.zero);
      final rpcRequest = jsonDecode(peer.channel.sent.last) as Map;
      expect(rpcRequest['name'], 'dashboard_widgetRPC');
      expect(rpcRequest['args'], ['pressbutton', 'widget-1', 'Start']);
      peer.channel.emitMessage(
        jsonEncode({'responseId': rpcRequest['requestId'], 'result': true}),
      );
      expect(await rpcFuture, isTrue);

      final bindFuture = connection.bindSlot('slot-1', 'light-1');
      await Future<void>.delayed(Duration.zero);
      final bindRequest = jsonDecode(peer.channel.sent.last) as Map;
      expect(bindRequest['name'], 'satellite_resourceBind');
      peer.channel.emitMessage(
        jsonEncode({'responseId': bindRequest['requestId'], 'result': null}),
      );
      await bindFuture;
      expect(connection.slots.single.resourceId, 'light-1');

      peer.channel.emitMessage(
        jsonEncode({
          'requestId': 'resource-1',
          'name': 'satellite_resourceRPC',
          'args': ['slot-1', 'setLightState', '#ffffff', true, 0.2],
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(jsonDecode(peer.channel.sent.last), {
        'responseId': 'resource-1',
        'result': {'lightOn': true},
      });

      await connection.disconnect();
      connection.dispose();
      signaling.dispose();
    },
  );
}

Future<Directory> createTemporaryDirectory(String prefix) async =>
    await Directory.systemTemp.createTemp(prefix);

class _FakeCloudPubSubSocket implements CloudPubSubSocket {
  final messagesController = StreamController<dynamic>.broadcast();
  final sent = <String>[];

  @override
  Stream<dynamic> get messages => messagesController.stream;

  @override
  void add(String message) => sent.add(message);

  @override
  Future<void> close() async {
    await messagesController.close();
  }
}

class _FakeDataChannel implements SatelliteDataChannel {
  SatelliteChannelState _state = SatelliteChannelState.connecting;
  final sent = <String>[];
  void Function(SatelliteChannelState state)? _onStateChanged;
  void Function(String message)? _onMessage;

  @override
  String get label => 'controlChannel';

  @override
  SatelliteChannelState get state => _state;

  @override
  set onStateChanged(void Function(SatelliteChannelState state)? listener) {
    _onStateChanged = listener;
  }

  @override
  set onMessage(void Function(String message)? listener) {
    _onMessage = listener;
  }

  @override
  Future<void> sendText(String message) async => sent.add(message);

  @override
  Future<void> close() async => emitState(SatelliteChannelState.closed);

  void emitState(SatelliteChannelState state) {
    _state = state;
    _onStateChanged?.call(state);
  }

  void emitMessage(String message) => _onMessage?.call(message);
}

class _FakePeerConnection implements SatellitePeerConnection {
  final channel = _FakeDataChannel();
  void Function(SatellitePeerState state)? _onStateChanged;

  @override
  set onIceCandidate(void Function(SatelliteIceCandidate candidate)? listener) {
    // The test drives signaling through the fake socket directly.
  }

  @override
  set onDataChannel(void Function(SatelliteDataChannel channel)? listener) {
    // The locally-created channel is returned by createDataChannel.
  }

  @override
  set onStateChanged(void Function(SatellitePeerState state)? listener) {
    _onStateChanged = listener;
  }

  @override
  Future<SatelliteDataChannel> createDataChannel(String label) async => channel;

  @override
  Future<SatelliteSessionDescription> createOffer() async =>
      const SatelliteSessionDescription(sdp: 'offer', type: 'offer');

  @override
  Future<void> setLocalDescription(
    SatelliteSessionDescription description,
  ) async {}

  @override
  Future<SatelliteSessionDescription?> getLocalDescription() async =>
      const SatelliteSessionDescription(sdp: 'offer', type: 'offer');

  @override
  Future<void> setRemoteDescription(
    SatelliteSessionDescription description,
  ) async {}

  @override
  Future<void> addCandidate(SatelliteIceCandidate candidate) async {}

  @override
  Future<void> close() async {}

  @override
  Future<void> dispose() async {}

  void emitPeerState(SatellitePeerState state) => _onStateChanged?.call(state);
}
