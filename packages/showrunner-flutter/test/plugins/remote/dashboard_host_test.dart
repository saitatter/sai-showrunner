import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/remote/dashboard_host.dart';
import 'package:showrunner_flutter/plugins/remote/manifest.dart';
import 'package:showrunner_flutter/plugins/remote/satellite.dart';
import 'package:showrunner_flutter/plugins/spellcast/cloud_pubsub.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';

void main() {
  test(
    'accepts a shared dashboard and serves its config and widget RPC',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'dashboard-host-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final dataService = ShowRunnerDataService(directory);
      await dataService.savePluginSettings('twitch', {
        'accessToken': 'token',
        'broadcasterId': 'owner-1',
      });
      await ResourceRepository(Directory('${directory.path}/dashboards')).save(
        const ResourceData(
          id: 'dash-1',
          config: {
            'name': 'Studio dashboard',
            'cloudId': 'cloud-1',
            'remoteTwitchIds': ['satellite-1'],
            'pages': [
              {
                'id': 'page-1',
                'sections': [
                  {
                    'id': 'section-1',
                    'widgets': [
                      {
                        'id': 'button-1',
                        'plugin': 'remote',
                        'widget': 'button',
                        'config': {'triggerName': 'Start'},
                      },
                    ],
                  },
                ],
              },
            ],
            'resourceSlots': [],
          },
        ),
      );

      final socket = _FakeCloudPubSubSocket();
      final signaling = SatelliteSignalingController(
        dataService: dataService,
        negotiator: (_) async => 'wss://cloud.example.test/client',
        socketFactory: (_) async => socket,
      );
      final eventHub = DartPluginEventHub();
      final events = <Map<String, dynamic>>[];
      final eventSubscription = eventHub
          .stream('remoteButton')
          .listen(events.add);
      final registry = DartPluginRegistry()
        ..register(createRemotePlugin(eventHub: eventHub));
      final peer = _FakePeerConnection();
      final host = RemoteDashboardHost(
        dataService: dataService,
        registry: registry,
        eventHub: eventHub,
        signaling: signaling,
        peerFactory: (_) async => peer,
      );

      await host.start();
      socket.messagesController.add(
        jsonEncode({
          'type': 'message',
          'dataType': 'json',
          'data': {
            'plugin': 'satellite',
            'event': 'satelliteConnectionIceCandidate',
            'context': {
              'satelliteService': 'twitch',
              'satelliteId': 'satellite-1',
              'ShowRunnerService': 'twitch',
              'ShowRunnerId': 'owner-1',
              'dashId': 'dash-1',
              'side': 'satellite',
              'candidate': {'candidate': 'candidate-before-offer'},
            },
          },
        }),
      );
      await _settle();
      socket.messagesController.add(
        jsonEncode({
          'type': 'message',
          'dataType': 'json',
          'data': {
            'plugin': 'satellite',
            'event': 'satelliteConnectionRequest',
            'context': {
              'satelliteService': 'twitch',
              'satelliteId': 'satellite-1',
              'ShowRunnerService': 'twitch',
              'ShowRunnerId': 'owner-1',
              'dashId': 'dash-1',
              'sdp': {'sdp': 'offer', 'type': 'offer'},
            },
          },
        }),
      );
      await _settle();

      expect(jsonDecode(socket.sent.single), {
        'type': 'event',
        'event': 'satellite_satelliteConnectionResponse',
        'dataType': 'json',
        'data': {
          'satelliteService': 'twitch',
          'satelliteId': 'satellite-1',
          'ShowRunnerService': 'twitch',
          'ShowRunnerId': 'owner-1',
          'dashId': 'dash-1',
          'sdp': {'sdp': 'answer', 'type': 'answer'},
        },
      });
      expect(peer.addedCandidates.single.candidate, 'candidate-before-offer');

      final channel = _FakeDataChannel();
      peer.emitDataChannel(channel);
      channel.emitState(SatelliteChannelState.open);
      await _settle();
      final configRequest = jsonDecode(channel.sent.single) as Map;
      expect(configRequest['name'], 'dashboard_setConfig');
      expect(
        (configRequest['args'] as List).single['name'],
        'Studio dashboard',
      );
      channel.emitMessage(
        jsonEncode({'responseId': configRequest['requestId'], 'result': null}),
      );

      channel.emitMessage(
        jsonEncode({
          'requestId': 'widget-1',
          'name': 'dashboard_widgetRPC',
          'args': ['pressbutton', 'button-1', 'Start'],
        }),
      );
      await _settle();
      expect(events, [
        {'name': 'Start'},
      ]);
      expect(jsonDecode(channel.sent.last), {
        'responseId': 'widget-1',
        'result': true,
      });

      await eventSubscription.cancel();
      await host.stop();
      host.dispose();
      await signaling.stop();
      signaling.dispose();
      await registry.close();
      await eventHub.dispose();
    },
  );
}

Future<void> _settle() async {
  await Future<void>.delayed(const Duration(milliseconds: 20));
}

class _FakeCloudPubSubSocket implements CloudPubSubSocket {
  final messagesController = StreamController<dynamic>.broadcast();
  final sent = <String>[];

  @override
  Stream<dynamic> get messages => messagesController.stream;

  @override
  void add(String message) => sent.add(message);

  @override
  Future<void> close() async => messagesController.close();
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
  void Function(SatellitePeerState state)? _onStateChanged;
  void Function(SatelliteDataChannel channel)? _onDataChannel;
  final addedCandidates = <SatelliteIceCandidate>[];

  @override
  set onIceCandidate(
    void Function(SatelliteIceCandidate candidate)? listener,
  ) {}

  @override
  set onDataChannel(void Function(SatelliteDataChannel channel)? listener) {
    _onDataChannel = listener;
  }

  @override
  set onStateChanged(void Function(SatellitePeerState state)? listener) {
    _onStateChanged = listener;
  }

  @override
  Future<SatelliteDataChannel> createDataChannel(String label) async {
    throw UnsupportedError('The host must receive the control channel.');
  }

  @override
  Future<SatelliteSessionDescription> createOffer() async =>
      const SatelliteSessionDescription(sdp: 'offer', type: 'offer');

  @override
  Future<SatelliteSessionDescription> createAnswer() async =>
      const SatelliteSessionDescription(sdp: 'answer', type: 'answer');

  @override
  Future<void> setLocalDescription(
    SatelliteSessionDescription description,
  ) async {}

  @override
  Future<SatelliteSessionDescription?> getLocalDescription() async =>
      const SatelliteSessionDescription(sdp: 'answer', type: 'answer');

  @override
  Future<void> setRemoteDescription(
    SatelliteSessionDescription description,
  ) async {}

  @override
  Future<void> addCandidate(SatelliteIceCandidate candidate) async =>
      addedCandidates.add(candidate);

  @override
  Future<void> close() async =>
      _onStateChanged?.call(SatellitePeerState.closed);

  @override
  Future<void> dispose() async {}

  void emitDataChannel(SatelliteDataChannel channel) =>
      _onDataChannel?.call(channel);
}
