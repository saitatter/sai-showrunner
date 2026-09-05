import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/obs/actions.dart';
import 'package:showrunner_flutter/plugins/obs/connection_router.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  test('routes requests through the configured default OBS resource', () async {
    ObsConnectionEndpoint? createdEndpoint;
    var calls = <String>[];
    var closed = false;
    final transport = _RecordingTransport(
      onCall: (request) => calls.add(request),
      onClose: () => closed = true,
    );
    final router = ObsConnectionRouter(
      dataService: ShowRunnerDataService(Directory.systemTemp),
      settingsLoader: () async => {'obsDefault': 'studio'},
      resourceLoader: () async => [
        const ResourceData(
          id: 'studio',
          config: {
            'name': 'Studio OBS',
            'host': '10.0.0.20',
            'port': 4455,
            'password': 'secret',
          },
        ),
      ],
      transportFactory: (endpoint, _) {
        createdEndpoint = endpoint;
        return transport;
      },
    );

    final endpoint = await router.resolveEndpoint();
    await router.call('GetVersion', {});
    await router.call('GetStreamStatus', {});

    expect(endpoint.id, 'studio');
    expect(endpoint.host, '10.0.0.20');
    expect(endpoint.port, 4455);
    expect(endpoint.password, 'secret');
    expect(createdEndpoint?.cacheKey, endpoint.cacheKey);
    expect(calls, ['GetVersion', 'GetStreamStatus']);

    await router.close();
    expect(closed, isTrue);
  });

  test(
    'falls back to global OBS settings when no resource is selected',
    () async {
      final router = ObsConnectionRouter(
        dataService: ShowRunnerDataService(Directory.systemTemp),
        settingsLoader: () async => {'host': '127.0.0.1', 'port': 4455},
        resourceLoader: () async => [
          const ResourceData(id: 'one', config: {'name': 'One'}),
          const ResourceData(id: 'two', config: {'name': 'Two'}),
        ],
        transportFactory: (endpoint, _) => _RecordingTransport(),
      );

      final endpoint = await router.resolveEndpoint();

      expect(endpoint.id, 'settings');
      expect(endpoint.host, '127.0.0.1');
      expect(endpoint.port, 4455);
    },
  );

  test('exposes the reference OBS state providers', () {
    final plugin = createObsPlugin(CallbackObsTransport((_, _) async => {}));
    expect(
      plugin.states.map((state) => state.id),
      containsAll(<String>['connected', 'scene', 'streaming', 'recording']),
    );
  });
}

final class _RecordingTransport implements ObsTransport {
  _RecordingTransport({this.onCall, this.onClose});

  final void Function(String request)? onCall;
  final void Function()? onClose;

  @override
  Future<Map<String, dynamic>> call(
    String request,
    Map<String, dynamic> data,
  ) async {
    onCall?.call(request);
    return <String, dynamic>{};
  }

  @override
  Future<void> close() async => onClose?.call();
}
