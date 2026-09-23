import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/obs/actions.dart';
import 'package:showrunner_flutter/plugins/obs/connection_router.dart';
import 'package:showrunner_flutter/plugins/obs/overlay_source_service.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  late Directory userDirectory;

  setUp(() async {
    userDirectory = await Directory.systemTemp.createTemp(
      'showrunner-overlay-obs-',
    );
  });

  tearDown(() async {
    if (await userDirectory.exists()) {
      await userDirectory.delete(recursive: true);
    }
  });

  test('inspects the explicitly selected OBS connection and source', () async {
    final calls = <(String, Map<String, dynamic>)>[];
    ObsConnectionEndpoint? endpoint;
    final service = _service(
      userDirectory,
      transportFactory: (next, _) {
        endpoint = next;
        return _FakeObsTransport((request, data) async {
          calls.add((request, data));
          return switch (request) {
            'GetCurrentProgramScene' => {'currentProgramSceneName': 'Live'},
            'GetInputList' => {
              'inputs': [
                {'inputName': 'Overlay Browser'},
              ],
            },
            'GetInputSettings' => {
              'inputSettings': {
                'url': 'http://localhost:8181/overlays/overlay-1',
                'width': 1920,
                'height': 1080,
              },
            },
            _ => const {},
          };
        });
      },
    );

    final status = await service.inspect(
      connectionId: 'studio',
      overlayId: 'overlay-1',
      width: 1920,
      height: 1080,
      port: 8181,
    );

    expect(endpoint?.id, 'studio');
    expect(endpoint?.host, '10.0.0.2');
    expect(status.connected, isTrue);
    expect(status.sceneName, 'Live');
    expect(status.sourceName, 'Overlay Browser');
    expect(status.isCurrent, isTrue);
    expect(calls.map((call) => call.$1), [
      'GetVersion',
      'GetCurrentProgramScene',
      'GetInputList',
      'GetInputSettings',
    ]);

    await service.close();
  });

  test('creates a browser source in the current program scene', () async {
    final requests = <(String, Map<String, dynamic>)>[];
    final service = _service(
      userDirectory,
      transportFactory: (_, _) => _FakeObsTransport((request, data) async {
        requests.add((request, data));
        if (request == 'GetCurrentProgramScene') {
          return {'currentProgramSceneName': 'Live'};
        }
        return const {};
      }),
    );

    await service.createBrowserSource(
      connectionId: 'studio',
      overlayId: 'overlay-1',
      sourceName: 'Overlay Browser',
      width: 1280,
      height: 720,
      port: 8181,
    );

    expect(requests.last.$1, 'CreateInput');
    expect(requests.last.$2, {
      'sceneName': 'Live',
      'inputName': 'Overlay Browser',
      'inputKind': 'browser_source',
      'inputSettings': {
        'url': 'http://localhost:8181/overlays/overlay-1',
        'width': 1280,
        'height': 720,
      },
    });
    await service.close();
  });

  test('repairs the URL and canvas dimensions of an existing source', () async {
    (String, Map<String, dynamic>)? request;
    final service = _service(
      userDirectory,
      transportFactory: (_, _) => _FakeObsTransport((name, data) async {
        if (name == 'SetInputSettings') request = (name, data);
        return const {};
      }),
    );

    await service.fixBrowserSource(
      connectionId: 'studio',
      overlayId: 'overlay-1',
      sourceName: 'Overlay Browser',
      width: 1280,
      height: 720,
      port: 8181,
    );

    expect(request?.$1, 'SetInputSettings');
    expect(request?.$2, {
      'inputName': 'Overlay Browser',
      'inputSettings': {
        'url': 'http://localhost:8181/overlays/overlay-1',
        'width': 1280,
        'height': 720,
      },
      'overlay': true,
    });
    await service.close();
  });

  test(
    'remote OBS gets the ShowRunner LAN address in the browser URL',
    () async {
      final service = _service(
        userDirectory,
        localAddressLoader: () async => '192.168.1.25',
        resources: [
          const ResourceData(
            id: 'remote',
            config: {
              'name': 'Remote OBS',
              'host': '10.0.0.5',
              'port': 4455,
              'local': false,
            },
          ),
        ],
      );

      expect(
        await service.browserSourceUrl(
          connectionId: 'remote',
          overlayId: 'overlay-1',
          port: 8181,
        ),
        'http://192.168.1.25:8181/overlays/overlay-1',
      );
      await service.close();
    },
  );
}

OverlayObsSourceService _service(
  Directory userDirectory, {
  ObsTransportFactory? transportFactory,
  Future<String> Function()? localAddressLoader,
  List<ResourceData>? resources,
}) => OverlayObsSourceService(
  dataService: ShowRunnerDataService(userDirectory),
  router: ObsConnectionRouter(
    dataService: ShowRunnerDataService(userDirectory),
    settingsLoader: () async => {'obsDefault': 'default'},
    resourceLoader: () async =>
        resources ??
        [
          const ResourceData(
            id: 'default',
            config: {
              'name': 'Default OBS',
              'host': '127.0.0.1',
              'port': 4455,
              'local': true,
            },
          ),
          const ResourceData(
            id: 'studio',
            config: {
              'name': 'Studio OBS',
              'host': '10.0.0.2',
              'port': 4456,
              'password': 'secret',
              'local': true,
            },
          ),
        ],
    transportFactory:
        transportFactory ??
        (_, _) => _FakeObsTransport((_, _) async => const {}),
  ),
  defaultConnectionLoader: () async => 'default',
  localAddressLoader: localAddressLoader,
);

final class _FakeObsTransport implements ObsTransport {
  const _FakeObsTransport(this.onCall);

  final Future<Map<String, dynamic>> Function(
    String request,
    Map<String, dynamic> data,
  )
  onCall;

  @override
  Future<Map<String, dynamic>> call(
    String request,
    Map<String, dynamic> data,
  ) => onCall(request, data);

  @override
  Future<void> close() async {}
}
