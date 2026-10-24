import '../../spellcast/cloud_pubsub.dart';

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

  void validate() {
    if (satelliteService != 'twitch' || showRunnerService != 'twitch') {
      throw const FormatException('Unsupported satellite identity provider.');
    }
    for (final value in [satelliteId, showRunnerId, dashboardId]) {
      if (value.isEmpty ||
          value.length > 128 ||
          value.trim() != value ||
          value.contains('\u0000')) {
        throw const FormatException('Invalid satellite session identity.');
      }
    }
  }

  factory SatelliteConnectionConfig.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Satellite session must be an object.');
    }
    String field(String key) {
      final item = value[key];
      if (item is! String) {
        throw const FormatException(
          'Satellite session fields must be strings.',
        );
      }
      return item;
    }

    final config = SatelliteConnectionConfig(
      satelliteService: field('satelliteService'),
      satelliteId: field('satelliteId'),
      showRunnerService: field('ShowRunnerService'),
      showRunnerId: field('ShowRunnerId'),
      dashboardId: field('dashId'),
    );
    config.validate();
    return config;
  }

  SatelliteJson toJson() => {
    'satelliteService': satelliteService,
    'satelliteId': satelliteId,
    'ShowRunnerService': showRunnerService,
    'ShowRunnerId': showRunnerId,
    'dashId': dashboardId,
  };

  bool matches(Object? value) {
    try {
      final next = SatelliteConnectionConfig.fromJson(value);
      return next.satelliteService == satelliteService &&
          next.satelliteId == satelliteId &&
          next.showRunnerService == showRunnerService &&
          next.showRunnerId == showRunnerId &&
          next.dashboardId == dashboardId;
    } on FormatException {
      return false;
    }
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
    final sdp = value['sdp'];
    final type = value['type'];
    if (sdp is! String ||
        sdp.isEmpty ||
        sdp.length > 262144 ||
        type is! String ||
        !{'offer', 'answer'}.contains(type)) {
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
    final candidate = value['candidate'];
    final mid = value['sdpMid'];
    final index = value['sdpMLineIndex'];
    if (candidate is! String ||
        candidate.isEmpty ||
        candidate.length > 8192 ||
        (mid != null && (mid is! String || mid.length > 128)) ||
        (index != null && (index is! int || index < 0 || index > 65535))) {
      throw const FormatException('Satellite ICE candidate is empty.');
    }
    return SatelliteIceCandidate(
      candidate: candidate,
      sdpMid: mid as String?,
      sdpMLineIndex: index as int?,
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
