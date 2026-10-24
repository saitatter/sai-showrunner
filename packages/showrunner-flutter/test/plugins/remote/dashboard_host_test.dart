import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/remote/dashboard_host.dart';
import 'package:showrunner_flutter/plugins/remote/manifest.dart';
import 'package:showrunner_flutter/plugins/remote/satellite.dart';
import 'package:showrunner_flutter/plugins/remote/remote_protocol.generated.dart';
import 'package:showrunner_flutter/plugins/spellcast/cloud_pubsub.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/plugins/variables/manifest.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/graph/runtime/graph_execution_engine.dart';
import '../../support/graph_fixtures.dart';

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
        ..register(createRemotePlugin(eventHub: eventHub))
        ..register(createVariablesPlugin());
      final graphResults = <Future<void>>[];
      final trigger = registry.findPlugin('remote')!.triggers.single;
      final graphListener = trigger.listenFromRuntime().listen((event) {
        if (!trigger.matchesRuntime({'name': 'Start'}, event)) return;
        graphResults.add(
          CompiledExecutionEngine()
              .executeWithRegistry(
                automation: automationFixture(
                  entryNodeId: 'record',
                  nodes: [
                    GraphNode(
                      id: 'record',
                      type: actionNodeType('variables', 'set'),
                      data: {
                        'config': {
                          'variable': 'remoteProof',
                          'value': '{{name}}',
                        },
                      },
                    ),
                  ],
                  connections: [],
                ),
                context: EvaluationContext(locals: event),
                registry: registry,
              )
              .then((result) {
                expect(result.completed, true);
                expect(result.nodeResults['record']?['value'], 'Start');
              }),
        );
      });
      final peer = _FakePeerConnection();
      var peersCreated = 0;
      var sharedDashboard = await ResourceRepository(
        Directory('${directory.path}/dashboards'),
      ).load('dash-1');
      final host = RemoteDashboardHost(
        dataService: dataService,
        registry: registry,
        eventHub: eventHub,
        signaling: signaling,
        peerFactory: (_) async {
          peersCreated++;
          return peer;
        },
        dashboardLoader: (_) async => sharedDashboard,
      );

      await host.start();
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
              'sdp': {'sdp': 42, 'type': 'offer'},
            },
          },
        }),
      );
      await _settle();
      expect(peersCreated, 0);
      expect(host.connectionIds, isEmpty);
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
      await Future.wait(graphResults);
      expect(graphResults, hasLength(1));
      for (final args in [
        ['pressbutton', 'button-1', 'Forged'],
        ['pressbutton', 'missing', 'Start'],
      ]) {
        channel.emitMessage(
          jsonEncode({
            'requestId': 'reject-${args[1]}',
            'name': 'dashboard_widgetRPC',
            'args': args,
          }),
        );
      }
      await _settle();
      expect(events, hasLength(1));
      channel.autoAcknowledge = true;
      registry.updateDynamicState('variables', 'counter', 1);
      channel.emitMessage(
        jsonEncode({
          'requestId': 'subscribe',
          'name': 'dashboard_acquireState',
          'args': ['variables', 'counter'],
        }),
      );
      await _settle();
      List<Map> updates() => channel.sent
          .map((s) => jsonDecode(s) as Map)
          .where((m) => m['name'] == 'dashboard_stateUpdate')
          .toList();
      expect(updates().last['args'], ['variables', 'counter', 1]);
      registry.updateDynamicState('variables', 'counter', 2);
      await _settle();
      expect(updates().last['args'], ['variables', 'counter', 2]);
      channel.emitMessage(
        jsonEncode({
          'requestId': 'unsubscribe',
          'name': 'dashboard_freeState',
          'args': ['variables', 'counter'],
        }),
      );
      await _settle();
      final count = updates().length;
      registry.updateDynamicState('variables', 'counter', 3);
      await _settle();
      expect(updates(), hasLength(count));
      channel.emitState(SatelliteChannelState.closed);
      await _settle();
      expect(host.connectionIds, isEmpty);
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
              'sdp': {'sdp': 'new-offer', 'type': 'offer'},
            },
          },
        }),
      );
      await _settle();
      expect(host.connectionIds, hasLength(1));
      final reconnected = _FakeDataChannel()..autoAcknowledge = true;
      peer.emitDataChannel(reconnected);
      reconnected.emitState(SatelliteChannelState.open);
      await _settle();
      reconnected.emitMessage(
        jsonEncode({
          'requestId': 'resubscribe',
          'name': 'dashboard_acquireState',
          'args': ['variables', 'counter'],
        }),
      );
      await _settle();
      registry.updateDynamicState('variables', 'counter', 4);
      await _settle();
      final latest = reconnected.sent
          .map((s) => jsonDecode(s) as Map)
          .lastWhere((m) => m['name'] == 'dashboard_stateUpdate');
      expect(latest['args'], ['variables', 'counter', 4]);
      reconnected.emitMessage(
        jsonEncode({
          'requestId': 'press-again',
          'name': 'dashboard_widgetRPC',
          'args': ['pressbutton', 'button-1', 'Start'],
        }),
      );
      await _settle();
      await Future.wait(graphResults);
      expect(graphResults, hasLength(2));

      final original = sharedDashboard!;
      sharedDashboard = ResourceData(
        id: original.id,
        config: {...original.config, 'pages': []},
      );
      reconnected.emitMessage(
        jsonEncode({
          'requestId': 'deleted-button',
          'name': 'dashboard_widgetRPC',
          'args': ['pressbutton', 'button-1', 'Start'],
        }),
      );
      expect(
        (await _response(reconnected, 'deleted-button'))['result'],
        isNull,
      );
      expect(events, hasLength(2));

      sharedDashboard = ResourceData(
        id: original.id,
        config: {
          ...original.config,
          'remoteTwitchIds': ['another-user'],
        },
      );
      reconnected.emitMessage(
        jsonEncode({
          'requestId': 'revoked-access',
          'name': 'dashboard_widgetRPC',
          'args': ['pressbutton', 'button-1', 'Start'],
        }),
      );
      expect(
        (await _response(reconnected, 'revoked-access')).containsKey('failed'),
        isTrue,
      );
      expect(events, hasLength(2));
      await host.refreshDashboard('dash-1');
      expect(host.connectionIds, isEmpty);
      reconnected.emitMessage(
        jsonEncode({
          'requestId': 'stale-session',
          'name': 'dashboard_widgetRPC',
          'args': ['pressbutton', 'button-1', 'Start'],
        }),
      );
      await _settle();
      expect(events, hasLength(2));

      await graphListener.cancel();
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

Future<Map> _response(_FakeDataChannel channel, String requestId) async {
  final deadline = Stopwatch()..start();
  while (deadline.elapsed < const Duration(seconds: 3)) {
    final response = channel.sent
        .map((raw) => jsonDecode(raw) as Map)
        .where((value) => value['responseId'] == requestId)
        .firstOrNull;
    if (response != null) return response;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  throw StateError('Missing synthetic dashboard response.');
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
  bool autoAcknowledge = false;
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
  Future<void> sendText(String message) async {
    final decoded = decodeRemoteWire(jsonDecode(message), 'dash-1');
    sent.add(jsonEncode(decoded));
    if (autoAcknowledge && decoded['requestId'] != null) {
      scheduleMicrotask(
        () => emitMessage(
          jsonEncode({'responseId': decoded['requestId'], 'result': null}),
        ),
      );
    }
  }

  @override
  Future<void> close() async => emitState(SatelliteChannelState.closed);

  void emitState(SatelliteChannelState state) {
    _state = state;
    _onStateChanged?.call(state);
  }

  void emitMessage(String message) => _onMessage?.call(
    jsonEncode(
      encodeRemoteWire(jsonDecode(message) as Map<String, dynamic>, 'dash-1'),
    ),
  );
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
