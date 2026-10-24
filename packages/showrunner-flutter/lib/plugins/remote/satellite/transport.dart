import 'protocol.dart';
import 'resources.dart';

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
