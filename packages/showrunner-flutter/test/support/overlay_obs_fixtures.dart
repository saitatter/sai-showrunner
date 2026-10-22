import 'dart:async';
import 'package:showrunner_flutter/plugins/obs/overlay_source_service.dart';

typedef ObsFixtureRequest = ({
  String connection,
  String overlay,
  int width,
  int height,
  int port,
});

final class RecordingOverlayObsActions implements OverlayObsSourceActions {
  RecordingOverlayObsActions({this.label = 'Fixture'});
  final String label;
  Future<List<ObsConnectionChoice>> Function()? list;
  Future<OverlayBrowserSourceStatus> Function(ObsFixtureRequest)?
  inspectRequest;
  Completer<void>? writeGate;
  bool failWrite = false, failOpen = false;
  int defaultReads = 0, closes = 0;
  final inspected = <ObsFixtureRequest>[],
      created = <ObsFixtureRequest>[],
      fixed = <ObsFixtureRequest>[];
  final opened = <String>[];
  @override
  Future<List<ObsConnectionChoice>> listConnections() async => list != null
      ? list!()
      : [
          for (final id in ['a', 'b'])
            ObsConnectionChoice(
              id: id,
              name: '$label $id',
              host: '127.0.0.1',
              port: 4456,
              isLocal: true,
            ),
        ];
  @override
  Future<String?> defaultConnectionId() async {
    defaultReads++;
    return 'a';
  }

  @override
  Future<String> browserSourceUrl({
    required String connectionId,
    required String overlayId,
    required int port,
  }) async => 'http://localhost:$port/overlays/$overlayId';
  @override
  Future<OverlayBrowserSourceStatus> inspect({
    required String connectionId,
    required String overlayId,
    required int width,
    required int height,
    required int port,
  }) async {
    final request = (
      connection: connectionId,
      overlay: overlayId,
      width: width,
      height: height,
      port: port,
    );
    inspected.add(request);
    return inspectRequest != null
        ? inspectRequest!(request)
        : const OverlayBrowserSourceStatus(
            connected: true,
            sourceName: 'Browser',
            isCurrent: true,
          );
  }

  @override
  Future<void> createBrowserSource({
    required String connectionId,
    required String overlayId,
    required String sourceName,
    required int width,
    required int height,
    required int port,
  }) async {
    created.add((
      connection: connectionId,
      overlay: overlayId,
      width: width,
      height: height,
      port: port,
    ));
    if (failWrite) throw StateError('private-obs-marker');
    await writeGate?.future;
  }

  @override
  Future<void> fixBrowserSource({
    required String connectionId,
    required String overlayId,
    required String sourceName,
    required int width,
    required int height,
    required int port,
  }) async {
    fixed.add((
      connection: connectionId,
      overlay: overlayId,
      width: width,
      height: height,
      port: port,
    ));
    if (failWrite) throw StateError('private-obs-marker');
    await writeGate?.future;
  }

  @override
  Future<bool> openObs(String connectionId) async {
    opened.add(connectionId);
    if (failOpen) throw StateError('private-obs-marker');
    return true;
  }

  @override
  Future<void> close() async {
    closes++;
  }
}
