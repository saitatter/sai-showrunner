import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/viewer_data_repository.dart';
import 'package:showrunner_flutter/plugins/http/manifest.dart';
import 'package:showrunner_flutter/plugins/overlays/manifest.dart';
import 'package:showrunner_flutter/plugins/overlays/websocket_bridge.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/schema/viewer_data.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';

// Launched only by tools/overlay_registry/transport-browser-smoke.mjs.
void main() {
  test('serves an isolated real overlay bridge to Chromium', () async {
    final path = Platform.environment['SHOWRUNNER_OVERLAY_SMOKE_DIRECTORY'];
    if (path == null) {
      throw StateError('Run the transport browser smoke launcher.');
    }
    final scratch = Directory(path);
    final server = DartHttpEndpointService(port: 0);
    final hub = DartPluginEventHub();
    final registry = DartPluginRegistry();
    final viewers = InMemoryViewerDataRepository();
    await viewers.saveDefinitions(const [
      ViewerVariableDefinition(name: 'score', type: 'number'),
      ViewerVariableDefinition(name: 'privateNote', type: 'string'),
    ]);
    const identity = ViewerIdentity(
      id: 'viewer-1',
      displayName: 'Public Viewer',
    );
    await viewers.setViewerValue('twitch', identity, 'score', 42);
    await viewers.setViewerValue(
      'twitch',
      identity,
      'privateNote',
      'private-browser-marker',
    );
    final bridge = DartOverlayWebSocketService(
      server: server,
      eventHub: hub,
      registry: registry,
      viewerDataRepository: viewers,
      webRoot: Directory('../showrunner-obs-overlay/dist/obs-overlay'),
      overlayStore: OverlayResourceStore(
        load: (id) async => id != 'browser-probe'
            ? null
            : const ResourceData(
                id: 'browser-probe',
                config: {
                  'name': 'Browser probe',
                  'size': {'width': 640, 'height': 360},
                  'widgets': [
                    {
                      'id': 'probe-leaderboard',
                      'plugin': 'overlays',
                      'widget': 'leaderboard',
                      'name': 'Scores',
                      'position': {'x': 0, 'y': 120},
                      'size': {'width': 640, 'height': 120},
                      'config': {
                        'count': 5,
                        'sortBy': 'score',
                        'sortOrder': -1,
                        'variables': [
                          {'variable': 'score'},
                        ],
                      },
                    },
                    {
                      'id': 'probe-label',
                      'plugin': 'overlays',
                      'widget': 'label',
                      'name': 'Probe',
                      'position': {'x': 0, 'y': 0},
                      'size': {'width': 640, 'height': 120},
                      'config': {'message': 'Authenticated bridge connected'},
                    },
                  ],
                },
              ),
        save: (_) async {},
      ),
    );
    try {
      await server.start();
      await File('${scratch.path}/host.json').writeAsString(
        jsonEncode({'url': bridge.browserSourceUrl('browser-probe')}),
      );
      final deadline = Stopwatch()..start();
      while (!await File('${scratch.path}/done').exists()) {
        if (deadline.elapsed > const Duration(seconds: 45)) {
          throw StateError('Browser smoke deadline expired.');
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    } finally {
      await bridge.dispose();
      await server.stop();
      await registry.close();
      await hub.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}
