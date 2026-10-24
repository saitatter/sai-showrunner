import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/remote/satellite/protocol.dart';

void main() {
  const config = SatelliteConnectionConfig(
    satelliteService: 'twitch',
    satelliteId: 'viewer',
    showRunnerService: 'twitch',
    showRunnerId: 'owner',
    dashboardId: 'dashboard',
  );
  test(
    'session identities reject coercion, separators and unsupported providers',
    () {
      expect(config.matches(config.toJson()), isTrue);
      for (final invalid in [
        {...config.toJson(), 'satelliteId': 42},
        {...config.toJson(), 'satelliteId': 'viewer\u0000extra'},
        {...config.toJson(), 'satelliteId': 'viewer '},
        {...config.toJson(), 'satelliteService': 'unsupported'},
      ]) {
        expect(
          () => SatelliteConnectionConfig.fromJson(invalid),
          throwsFormatException,
        );
        expect(config.matches(invalid), isFalse);
      }
    },
  );
  test(
    'SDP and ICE validate types and payload bounds before native delegation',
    () {
      expect(
        SatelliteSessionDescription.fromJson({
          'sdp': 'offer',
          'type': 'offer',
        }).sdp,
        'offer',
      );
      for (final invalid in [
        {'sdp': 42, 'type': 'offer'},
        {'sdp': 'offer', 'type': 'unsupported'},
        {'sdp': 'x' * 262145, 'type': 'offer'},
      ]) {
        expect(
          () => SatelliteSessionDescription.fromJson(invalid),
          throwsFormatException,
        );
      }
      for (final invalid in [
        {'candidate': 42},
        {'candidate': 'candidate', 'sdpMLineIndex': 0.5},
        {'candidate': 'candidate', 'sdpMLineIndex': -1},
        {'candidate': 'candidate', 'sdpMid': 42},
        {'candidate': 'x' * 8193},
      ]) {
        expect(
          () => SatelliteIceCandidate.fromJson(invalid),
          throwsFormatException,
        );
      }
      expect(
        SatelliteIceCandidate.fromJson({
          'candidate': 'candidate',
          'sdpMLineIndex': 0,
        }).sdpMLineIndex,
        0,
      );
    },
  );
}
