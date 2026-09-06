part of '../satellite.dart';

typedef SatelliteJson = Map<String, dynamic>;

enum SatelliteConnectionState { connecting, connected, disconnected }

enum SatellitePeerState {
  newState,
  connecting,
  connected,
  disconnected,
  failed,
  closed,
}

enum SatelliteChannelState { connecting, open, closing, closed }

final class SatelliteConnectionConfig {
  const SatelliteConnectionConfig({
    required this.satelliteService,
    required this.satelliteId,
    required this.showRunnerService,
    required this.showRunnerId,
    required this.dashboardId,
  });

  final String satelliteService;
  final String satelliteId;
  final String showRunnerService;
  final String showRunnerId;
  final String dashboardId;

  SatelliteJson toJson() => {
    'satelliteService': satelliteService,
    'satelliteId': satelliteId,
    'ShowRunnerService': showRunnerService,
    'ShowRunnerId': showRunnerId,
    'dashId': dashboardId,
  };

  bool matches(Object? value) {
    if (value is! Map) return false;
    return value['satelliteService']?.toString() == satelliteService &&
        value['satelliteId']?.toString() == satelliteId &&
        value['ShowRunnerService']?.toString() == showRunnerService &&
        value['ShowRunnerId']?.toString() == showRunnerId &&
        value['dashId']?.toString() == dashboardId;
  }
}

final class SatelliteSessionDescription {
  const SatelliteSessionDescription({required this.sdp, required this.type});

  final String sdp;
  final String type;

  SatelliteJson toJson() => {'sdp': sdp, 'type': type};

  factory SatelliteSessionDescription.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Satellite SDP must be an object.');
    }
    final sdp = value['sdp']?.toString() ?? '';
    final type = value['type']?.toString() ?? '';
    if (sdp.isEmpty || type.isEmpty) {
      throw const FormatException('Satellite SDP is incomplete.');
    }
    return SatelliteSessionDescription(sdp: sdp, type: type);
  }
}

final class SatelliteIceCandidate {
  const SatelliteIceCandidate({
    required this.candidate,
    this.sdpMid,
    this.sdpMLineIndex,
  });

  final String candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;

  SatelliteJson toJson() => {
    'candidate': candidate,
    if (sdpMid != null) 'sdpMid': sdpMid,
    if (sdpMLineIndex != null) 'sdpMLineIndex': sdpMLineIndex,
  };

  factory SatelliteIceCandidate.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Satellite ICE candidate must be an object.');
    }
    final candidate = value['candidate']?.toString() ?? '';
    if (candidate.isEmpty) {
      throw const FormatException('Satellite ICE candidate is empty.');
    }
    return SatelliteIceCandidate(
      candidate: candidate,
      sdpMid: value['sdpMid']?.toString(),
      sdpMLineIndex: (value['sdpMLineIndex'] as num?)?.toInt(),
    );
  }
}

final class SatelliteSignalingMessage {
  const SatelliteSignalingMessage({required this.event, required this.data});

  final String event;
  final SatelliteJson data;
}

typedef SatelliteSignalingNegotiator =
    Future<String> Function(String accessToken);
typedef SatelliteSignalingSocketFactory =
    Future<CloudPubSubSocket> Function(Uri uri);
