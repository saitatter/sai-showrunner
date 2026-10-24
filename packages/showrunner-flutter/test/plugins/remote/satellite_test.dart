import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/remote/satellite.dart';
import 'package:showrunner_flutter/plugins/remote/remote_protocol.generated.dart';
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

  test('stop invalidates negotiation before a socket can be opened', () async {
    final directory = await createTemporaryDirectory('satellite-stop-');
    addTearDown(() => directory.delete(recursive: true));
    final data = ShowRunnerDataService(directory);
    await data.savePluginSettings('twitch', {'accessToken': 'token'});
    final entered = Completer<void>();
    final negotiated = Completer<String>();
    var opens = 0;
    final signaling = SatelliteSignalingController(
      dataService: data,
      negotiator: (_) {
        entered.complete();
        return negotiated.future;
      },
      socketFactory: (_) async {
        opens++;
        return _FakeCloudPubSubSocket();
      },
    );
    final starting = signaling.start();
    await entered.future;
    final stopping = signaling.stop();
    negotiated.complete('wss://cloud.example.test/client');
    await Future.wait([starting, stopping]);
    expect(opens, 0);
    expect(signaling.isConnected, isFalse);
    await signaling.close();
    signaling.dispose();
  });

  test('close awaits and releases a socket returned after stop', () async {
    final directory = await createTemporaryDirectory('satellite-late-socket-');
    addTearDown(() => directory.delete(recursive: true));
    final data = ShowRunnerDataService(directory);
    await data.savePluginSettings('twitch', {'accessToken': 'token'});
    final entered = Completer<void>();
    final opened = Completer<CloudPubSubSocket>();
    final socket = _FakeCloudPubSubSocket();
    final signaling = SatelliteSignalingController(
      dataService: data,
      negotiator: (_) async => 'wss://cloud.example.test/client',
      socketFactory: (_) {
        entered.complete();
        return opened.future;
      },
    );
    final starting = signaling.start();
    await entered.future;
    var closed = false;
    final closing = signaling.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    opened.complete(socket);
    await starting;
    await closing;
    expect(socket.messagesController.isClosed, isTrue);
    expect(signaling.isConnected, isFalse);
    await signaling.start();
    expect(signaling.isConnected, isFalse);
    signaling.dispose();
  });

  test('disconnect awaits and disposes a late native peer', () async {
    final directory = await createTemporaryDirectory('satellite-late-peer-');
    addTearDown(() => directory.delete(recursive: true));
    final signaling = SatelliteSignalingController(
      dataService: ShowRunnerDataService(directory),
    );
    final entered = Completer<void>();
    final opened = Completer<SatellitePeerConnection>();
    final peer = _FakePeerConnection();
    final connection = RemoteSatelliteConnection(
      id: 'late',
      config: const SatelliteConnectionConfig(
        satelliteService: 'twitch',
        satelliteId: 'satellite-1',
        showRunnerService: 'twitch',
        showRunnerId: 'owner-1',
        dashboardId: 'dash-1',
      ),
      signaling: signaling,
      peerFactory: (_) {
        entered.complete();
        return opened.future;
      },
    );
    final starting = connection.start();
    await entered.future;
    var closed = false;
    final closing = connection.disconnect().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    opened.complete(peer);
    await starting;
    await closing;
    expect(peer.closeCount, 1);
    expect(peer.disposeCount, 1);
    expect(peer.channel.sent, isEmpty);
    connection.dispose();
    await signaling.close();
    signaling.dispose();
  });

  test('overlapping manager connects retain only the latest owner', () async {
    final directory = await createTemporaryDirectory('satellite-manager-');
    addTearDown(() => directory.delete(recursive: true));
    final data = ShowRunnerDataService(directory);
    await data.savePluginSettings('twitch', {'accessToken': 'token'});
    final sockets = <_FakeCloudPubSubSocket>[];
    final signaling = SatelliteSignalingController(
      dataService: data,
      negotiator: (_) async => 'wss://cloud.example.test/client',
      socketFactory: (_) async {
        final socket = _FakeCloudPubSubSocket();
        sockets.add(socket);
        return socket;
      },
    );
    final entered = Completer<void>();
    final opened = Completer<SatellitePeerConnection>();
    final firstPeer = _FakePeerConnection(), secondPeer = _FakePeerConnection();
    var created = 0;
    final manager = RemoteSatelliteConnectionManager(
      dataService: data,
      signaling: signaling,
      peerFactory: (_) {
        if (created++ == 0) {
          entered.complete();
          return opened.future;
        }
        return Future.value(secondPeer);
      },
    );
    const config = SatelliteConnectionConfig(
      satelliteService: 'twitch',
      satelliteId: 'satellite-1',
      showRunnerService: 'twitch',
      showRunnerId: 'owner-1',
      dashboardId: 'dash-1',
    );
    final first = manager.connect(config);
    final cancelled = expectLater(first, throwsStateError);
    await entered.future;
    final second = manager.connect(config);
    opened.complete(firstPeer);
    await cancelled;
    final latest = await second;
    expect(manager.connection, same(latest));
    expect(firstPeer.closeCount, 1);
    expect(firstPeer.disposeCount, 1);
    // Malformed SDP fails asynchronously; the manager must observe that error.
    sockets.last.messagesController.add(
      jsonEncode({
        'data': {
          'plugin': 'satellite',
          'event': 'satelliteConnectionResponse',
          'context': {
            ...config.toJson(),
            'sdp': {'sdp': 42, 'type': 'answer'},
          },
        },
      }),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(manager.lastError, isA<StateError>());
    expect(manager.connection, isNull);
    await manager.close();
    expect(secondPeer.closeCount, 1);
    expect(secondPeer.disposeCount, 1);
    manager.dispose();
    signaling.dispose();
  });

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

      peer.channel.emitMessage(
        jsonEncode({
          'requestId': 'bad-config',
          'name': 'dashboard_setConfig',
          'args': [
            {'pages': 'invalid'},
          ],
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(jsonDecode(peer.channel.sent.last)['failed'], isTrue);
      expect(connection.lastError, isA<StateError>());
      expect(connection.dashboard!.name, 'Studio dashboard');
      await connection.disconnect();
      connection.dispose();
      final sentBeforeLate = peer.channel.sent.length;
      peer.channel.emitMessage(
        jsonEncode({
          'requestId': 'late-after-dispose',
          'name': 'dashboard_stateUpdate',
          'args': ['probe', 'late', 1],
        }),
      );
      peer.channel.emitState(SatelliteChannelState.open);
      peer.emitPeerState(SatellitePeerState.connected);
      await Future<void>.delayed(Duration.zero);
      expect(peer.channel.sent, hasLength(sentBeforeLate));
      signaling.dispose();
    },
  );

  test('rejects a pending RPC when the control channel closes', () async {
    final directory = await createTemporaryDirectory('satellite-rpc-close-');
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
      id: 'connection-rpc-close',
      config: const SatelliteConnectionConfig(
        satelliteService: 'twitch',
        satelliteId: 'satellite-1',
        showRunnerService: 'twitch',
        showRunnerId: 'owner-1',
        dashboardId: 'dash-1',
      ),
      signaling: signaling,
      peerFactory: (_) async => peer,
    );

    await connection.start();
    peer.emitPeerState(SatellitePeerState.connected);
    peer.channel.emitState(SatelliteChannelState.open);
    final pending = connection.callRpc('dashboard_widgetRPC');
    final additional = List.generate(
      63,
      (_) => connection.callRpc('dashboard_widgetRPC'),
    );
    await expectLater(connection.callRpc('overflow'), throwsStateError);
    final settled = [
      for (final call in additional) expectLater(call, throwsStateError),
    ];
    await Future<void>.delayed(Duration.zero);

    peer.channel.emitState(SatelliteChannelState.closed);

    await expectLater(
      pending,
      throwsA(
        predicate<Object>(
          (error) =>
              error is StateError &&
              error.message == 'Remote dashboard control channel closed.',
        ),
      ),
    );
    await connection.disconnect();
    await Future.wait(settled);
    peer.emitPeerState(SatellitePeerState.connected);
    peer.channel.emitState(SatelliteChannelState.open);
    expect(connection.state, SatelliteConnectionState.disconnected);
    connection.dispose();
    signaling.dispose();
  });

  test('survives repeated satellite connection and RPC cycles', () async {
    final directory = await createTemporaryDirectory('satellite-soak-');
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

    const config = SatelliteConnectionConfig(
      satelliteService: 'twitch',
      satelliteId: 'satellite-1',
      showRunnerService: 'twitch',
      showRunnerId: 'owner-1',
      dashboardId: 'dash-1',
    );
    for (var cycle = 0; cycle < 25; cycle++) {
      late final _FakePeerConnection peer;
      final connection = RemoteSatelliteConnection(
        id: 'soak-$cycle',
        config: config,
        signaling: signaling,
        peerFactory: (_) async {
          peer = _FakePeerConnection();
          return peer;
        },
      );

      await connection.start();
      peer.emitPeerState(SatellitePeerState.connected);
      peer.channel.emitState(SatelliteChannelState.open);
      expect(connection.state, SatelliteConnectionState.connected);

      final rpc = connection.callRpc('dashboard_widgetRPC', [cycle]);
      await Future<void>.delayed(Duration.zero);
      final request = jsonDecode(peer.channel.sent.single) as Map;
      peer.channel.emitMessage(
        jsonEncode({'responseId': request['requestId'], 'result': cycle}),
      );
      expect(await rpc, cycle);

      if (cycle == 0) {
        final state = jsonEncode({
          'requestId': 'replay-probe',
          'name': 'dashboard_stateUpdate',
          'args': ['probe', 'value', 1],
        });
        peer.channel.emitMessage(state);
        await Future<void>.delayed(Duration.zero);
        expect(connection.states['probe']?['value'], 1);
        peer.channel.emitMessage(state);
        await Future<void>.delayed(Duration.zero);
        expect(connection.state, SatelliteConnectionState.disconnected);
      } else if (cycle == 1 || cycle == 2) {
        final wire = encodeRemoteWire({
          'requestId': 'invalid-probe',
          'name': 'dashboard_stateUpdate',
          'args': ['probe', 'value', 1],
        }, 'dash-1');
        wire[cycle == 1 ? 'resourceId' : 'protocolVersion'] = cycle == 1
            ? 'another-dashboard'
            : 99;
        peer.channel.emitWire(jsonEncode(wire));
        await Future<void>.delayed(Duration.zero);
        expect(connection.state, SatelliteConnectionState.disconnected);
        expect(connection.states['probe'], isNull);
      }

      await connection.disconnect();
      connection.dispose();
      expect(connection.state, SatelliteConnectionState.disconnected);
    }

    expect(socket.sent, hasLength(25));
    await signaling.stop();
    signaling.dispose();
  });
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
  void emitWire(String message) => _onMessage?.call(message);
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
  Future<void> sendText(String message) async =>
      sent.add(jsonEncode(decodeRemoteWire(jsonDecode(message), 'dash-1')));

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
  int closeCount = 0, disposeCount = 0;
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
  Future<SatelliteSessionDescription> createAnswer() async =>
      const SatelliteSessionDescription(sdp: 'answer', type: 'answer');

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
  Future<void> close() async {
    closeCount++;
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
  }

  void emitPeerState(SatellitePeerState state) => _onStateChanged?.call(state);
}
