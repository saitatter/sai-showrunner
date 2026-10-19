part of '../satellite.dart';

abstract interface class SatelliteDataChannel {
  String get label;
  SatelliteChannelState get state;
  set onStateChanged(void Function(SatelliteChannelState state)? listener);
  set onMessage(void Function(String message)? listener);
  Future<void> sendText(String message);
  Future<void> close();
}

abstract interface class SatellitePeerConnection {
  set onIceCandidate(void Function(SatelliteIceCandidate candidate)? listener);
  set onDataChannel(void Function(SatelliteDataChannel channel)? listener);
  set onStateChanged(void Function(SatellitePeerState state)? listener);
  Future<SatelliteDataChannel> createDataChannel(String label);
  Future<SatelliteSessionDescription> createOffer();
  Future<SatelliteSessionDescription> createAnswer();
  Future<void> setLocalDescription(SatelliteSessionDescription description);
  Future<SatelliteSessionDescription?> getLocalDescription();
  Future<void> setRemoteDescription(SatelliteSessionDescription description);
  Future<void> addCandidate(SatelliteIceCandidate candidate);
  Future<void> close();
  Future<void> dispose();
}

typedef SatellitePeerConnectionFactory =
    Future<SatellitePeerConnection> Function(
      Map<String, dynamic> configuration,
    );

typedef SatelliteResourceRpcHandler =
    Future<Object?> Function(
      RemoteResourceSlot slot,
      String method,
      List<dynamic> args,
    );

final class FlutterSatellitePeerConnection implements SatellitePeerConnection {
  FlutterSatellitePeerConnection(this._peer);

  final rtc.RTCPeerConnection _peer;

  @override
  set onIceCandidate(void Function(SatelliteIceCandidate candidate)? listener) {
    _peer.onIceCandidate = (candidate) {
      final value = candidate.candidate;
      if (listener == null || value == null || value.isEmpty) return;
      listener(
        SatelliteIceCandidate(
          candidate: value,
          sdpMid: candidate.sdpMid,
          sdpMLineIndex: candidate.sdpMLineIndex,
        ),
      );
    };
  }

  @override
  set onDataChannel(void Function(SatelliteDataChannel channel)? listener) {
    _peer.onDataChannel = (channel) {
      listener?.call(FlutterSatelliteDataChannel(channel));
    };
  }

  @override
  set onStateChanged(void Function(SatellitePeerState state)? listener) {
    _peer.onConnectionState = (state) {
      listener?.call(switch (state) {
        rtc.RTCPeerConnectionState.RTCPeerConnectionStateNew =>
          SatellitePeerState.newState,
        rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnecting =>
          SatellitePeerState.connecting,
        rtc.RTCPeerConnectionState.RTCPeerConnectionStateConnected =>
          SatellitePeerState.connected,
        rtc.RTCPeerConnectionState.RTCPeerConnectionStateDisconnected =>
          SatellitePeerState.disconnected,
        rtc.RTCPeerConnectionState.RTCPeerConnectionStateFailed =>
          SatellitePeerState.failed,
        rtc.RTCPeerConnectionState.RTCPeerConnectionStateClosed =>
          SatellitePeerState.closed,
      });
    };
  }

  @override
  Future<SatelliteDataChannel> createDataChannel(String label) async =>
      FlutterSatelliteDataChannel(
        await _peer.createDataChannel(label, rtc.RTCDataChannelInit()),
      );

  @override
  Future<SatelliteSessionDescription> createOffer() async {
    final description = await _peer.createOffer(<String, dynamic>{});
    return SatelliteSessionDescription(
      sdp: description.sdp ?? '',
      type: description.type ?? 'offer',
    );
  }

  @override
  Future<SatelliteSessionDescription> createAnswer() async {
    final description = await _peer.createAnswer(<String, dynamic>{});
    return SatelliteSessionDescription(
      sdp: description.sdp ?? '',
      type: description.type ?? 'answer',
    );
  }

  @override
  Future<void> setLocalDescription(SatelliteSessionDescription description) =>
      _peer.setLocalDescription(
        rtc.RTCSessionDescription(description.sdp, description.type),
      );

  @override
  Future<SatelliteSessionDescription?> getLocalDescription() async {
    final description = await _peer.getLocalDescription();
    if (description == null ||
        description.sdp == null ||
        description.type == null) {
      return null;
    }
    return SatelliteSessionDescription(
      sdp: description.sdp!,
      type: description.type!,
    );
  }

  @override
  Future<void> setRemoteDescription(SatelliteSessionDescription description) =>
      _peer.setRemoteDescription(
        rtc.RTCSessionDescription(description.sdp, description.type),
      );

  @override
  Future<void> addCandidate(SatelliteIceCandidate candidate) =>
      _peer.addCandidate(
        rtc.RTCIceCandidate(
          candidate.candidate,
          candidate.sdpMid,
          candidate.sdpMLineIndex,
        ),
      );

  @override
  Future<void> close() => _peer.close();

  @override
  Future<void> dispose() => _peer.dispose();
}

final class FlutterSatelliteDataChannel implements SatelliteDataChannel {
  FlutterSatelliteDataChannel(this._channel);

  final rtc.RTCDataChannel _channel;
  void Function(SatelliteChannelState state)? _onStateChanged;
  void Function(String message)? _onMessage;

  @override
  String get label => _channel.label ?? '';

  @override
  SatelliteChannelState get state => switch (_channel.state) {
    rtc.RTCDataChannelState.RTCDataChannelConnecting =>
      SatelliteChannelState.connecting,
    rtc.RTCDataChannelState.RTCDataChannelOpen => SatelliteChannelState.open,
    rtc.RTCDataChannelState.RTCDataChannelClosing =>
      SatelliteChannelState.closing,
    rtc.RTCDataChannelState.RTCDataChannelClosed =>
      SatelliteChannelState.closed,
    null => SatelliteChannelState.closed,
  };

  @override
  set onStateChanged(void Function(SatelliteChannelState state)? listener) {
    _onStateChanged = listener;
    _channel.onDataChannelState = (_) => _onStateChanged?.call(state);
  }

  @override
  set onMessage(void Function(String message)? listener) {
    _onMessage = listener;
    _channel.onMessage = (message) {
      if (!message.isBinary) _onMessage?.call(message.text);
    };
  }

  @override
  Future<void> sendText(String message) =>
      _channel.send(rtc.RTCDataChannelMessage(message));

  @override
  Future<void> close() => _channel.close();
}

Future<SatellitePeerConnection> createFlutterSatellitePeerConnection(
  Map<String, dynamic> configuration,
) async => FlutterSatellitePeerConnection(
  await rtc.createPeerConnection(configuration),
);
