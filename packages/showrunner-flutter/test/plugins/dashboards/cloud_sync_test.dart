import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/dashboards/cloud_sync.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  test('creates a cloud share and persists the returned id', () async {
    final root = await Directory.systemTemp.createTemp('showrunner-dashboard-');
    addTearDown(() => root.delete(recursive: true));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requests = <HttpRequest>[];
    final subscription = server.listen((request) async {
      requests.add(request);
      expect(request.method, 'POST');
      expect(request.uri.path, '/api/dashboard-access/');
      expect(
        request.headers.value(HttpHeaders.authorizationHeader),
        'Bearer twitch-token',
      );
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      expect(body['dashboardId'], 'dashboard-1');
      expect(body['allowedTwitchIds'], ['42']);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'_id': 'cloud-1'}));
      await request.response.close();
    });
    addTearDown(subscription.cancel);

    final dataService = ShowRunnerDataService(root);
    await dataService.savePluginSettings('twitch', {
      'accessToken': 'twitch-token',
    });
    await dataService.savePluginSettings('remote', {
      'apiBase': 'http://127.0.0.1:${server.port}',
    });

    final result = await DashboardCloudSyncService(dataService: dataService)
        .synchronize(
          const ResourceData(
            id: 'dashboard-1',
            config: {
              'name': 'Studio',
              'remoteTwitchIds': ['42'],
            },
          ),
        );

    expect(result.config['cloudId'], 'cloud-1');
    expect(requests, hasLength(1));
  });

  test('updates and removes an existing cloud share', () async {
    final root = await Directory.systemTemp.createTemp('showrunner-dashboard-');
    addTearDown(() => root.delete(recursive: true));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final methods = <String>[];
    final paths = <String>[];
    final subscription = server.listen((request) async {
      methods.add(request.method);
      paths.add(request.uri.path);
      await utf8.decoder.bind(request).drain();
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
    });
    addTearDown(subscription.cancel);

    final dataService = ShowRunnerDataService(root);
    await dataService.savePluginSettings('twitch', {
      'accessToken': 'twitch-token',
    });
    await dataService.savePluginSettings('remote', {
      'apiBase': 'http://127.0.0.1:${server.port}',
    });
    final service = DashboardCloudSyncService(dataService: dataService);

    final updated = await service.synchronize(
      const ResourceData(
        id: 'dashboard-1',
        config: {
          'name': 'Studio',
          'remoteTwitchIds': ['42', '43'],
          'cloudId': 'cloud-1',
        },
      ),
    );
    final unshared = await service.synchronize(
      const ResourceData(
        id: 'dashboard-1',
        config: {'name': 'Studio', 'remoteTwitchIds': [], 'cloudId': 'cloud-1'},
      ),
    );

    expect(updated.config['cloudId'], 'cloud-1');
    expect(unshared.config.containsKey('cloudId'), isFalse);
    expect(methods, ['PUT', 'DELETE']);
    expect(paths, [
      '/api/dashboard-access/cloud-1',
      '/api/dashboard-access/cloud-1',
    ]);
  });
}
