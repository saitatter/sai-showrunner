import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/persistence/viewer_data_repository.dart';
import 'package:showrunner_flutter/plugins/http/manifest.dart';
import 'package:showrunner_flutter/plugins/http/contracts.dart';
import 'package:showrunner_flutter/plugins/overlays/manifest.dart';
import 'package:showrunner_flutter/plugins/overlays/websocket_bridge.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_bootstrap.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';
import 'package:showrunner_flutter/plugins/remote/dashboard_host.dart';
import 'package:showrunner_flutter/plugins/remote/satellite.dart';

void main() {
  test(
    'an interrupted request body does not escape the HTTP error boundary',
    () async {
      final server = DartHttpEndpointService(port: 0);
      await server.start();
      final subscription = server
          .register(
            const HttpEndpointConfig(method: 'POST', route: '/interrupted'),
          )
          .listen((_) {});
      final socket = await Socket.connect('127.0.0.1', server.boundPort!);
      socket.write(
        'POST /plugins/endpoints/interrupted HTTP/1.1\r\nHost: localhost\r\nContent-Length: 100\r\n\r\npartial',
      );
      await socket.flush();
      socket.destroy();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final client = HttpClient();
      try {
        final response = await (await client.getUrl(
          Uri.parse('http://127.0.0.1:${server.boundPort}/unknown'),
        )).close();
        await response.drain<void>();
        expect(response.statusCode, 404);
      } finally {
        client.close(force: true);
        await subscription.cancel();
        await server.stop();
      }
    },
  );

  test(
    'HTTP isolates handler errors and rejects foreign browser origins',
    () async {
      final server = DartHttpEndpointService(port: 0);
      await server.start();
      server.addRequestHandler((request) async {
        throw StateError('fixture error');
      });
      final client = HttpClient();
      try {
        final uri = Uri.parse('http://127.0.0.1:${server.boundPort}/probe');
        final foreign = await client.getUrl(uri);
        foreign.headers.set('origin', 'https://foreign.invalid');
        final forbidden = await foreign.close();
        await forbidden.drain<void>();
        expect(forbidden.statusCode, 403);
        final failure = await (await client.getUrl(uri)).close();
        await failure.drain<void>();
        expect(failure.statusCode, 500);
      } finally {
        client.close(force: true);
        await server.stop();
      }
    },
  );
  test(
    'HTTP limits request bodies before dispatching endpoint events',
    () async {
      final server = DartHttpEndpointService(port: 0, maxBodyBytes: 8);
      await server.start();
      final events = <Map<String, dynamic>>[];
      final subscription = server
          .register(const HttpEndpointConfig(method: 'POST', route: '/limited'))
          .listen(events.add);
      final client = HttpClient();
      try {
        final request = await client.postUrl(
          Uri.parse(
            'http://127.0.0.1:${server.boundPort}/plugins/endpoints/limited',
          ),
        );
        request.write('oversized body');
        final response = await request.close();
        await response.drain<void>();
        expect(response.statusCode, 413);
        expect(events, isEmpty);
      } finally {
        client.close(force: true);
        await subscription.cancel();
        await server.stop();
      }
    },
  );

  test(
    'disposing an active dashboard host does not notify after disposal',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'showrunner-audit-dispose-',
      );
      final data = ShowRunnerDataService(root);
      final hub = DartPluginEventHub();
      final registry = createDefaultPluginRegistry(eventHub: hub);
      final signaling = SatelliteSignalingController(dataService: data);
      final host = RemoteDashboardHost(
        dataService: data,
        registry: registry,
        eventHub: hub,
        signaling: signaling,
      );
      await host.start();
      final errors = <Object>[];
      runZonedGuarded<void>(
        () {
          host.dispose();
        },
        (error, stack) {
          errors.add(error);
        },
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(errors, isEmpty);
      signaling.dispose();
      await hub.dispose();
      registry.dispose();
      await root.delete(recursive: true);
    },
  );
  test(
    'HTTP rejects encoded Windows traversal outside the overlay web root',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'showrunner-audit-http-',
      );
      final web = Directory('${root.path}/web');
      await Directory('${web.path}/assets').create(recursive: true);
      await File('${root.path}/marker.txt').writeAsString('AUDIT_MARKER_ONLY');
      final repository = ResourceRepository(Directory('${root.path}/overlays'));
      final hub = DartPluginEventHub();
      final registry = createDefaultPluginRegistry(eventHub: hub);
      final server = DartHttpEndpointService(port: 0);
      await server.start();
      final bridge = DartOverlayWebSocketService(
        server: server,
        eventHub: hub,
        overlayStore: OverlayResourceStore(
          load: repository.load,
          save: repository.save,
        ),
        registry: registry,
        viewerDataRepository: InMemoryViewerDataRepository(),
        webRoot: web,
      );
      final client = HttpClient();
      try {
        final uri = Uri.parse(
          'http://127.0.0.1:${server.boundPort}/overlays/assets/..%5C..%5Cmarker.txt',
        );
        final response = await (await client.getUrl(uri)).close();
        final body = await utf8.decoder.bind(response).join();
        expect(response.statusCode, 400);
        expect(body, isNot(contains('AUDIT_MARKER_ONLY')));
      } finally {
        client.close(force: true);
        await bridge.dispose();
        await server.stop();
        await hub.dispose();
        registry.dispose();
        await root.delete(recursive: true);
      }
    },
  );
}
