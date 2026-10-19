import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:showrunner_flutter/features/remote/remote_workspace.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('discovers a remote dashboard through the authenticated API', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-remote-integration-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    String? authorization;
    Uri? requestUri;
    final subscription = server.listen((request) async {
      authorization = request.headers.value(HttpHeaders.authorizationHeader);
      requestUri = request.uri;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode([
          {
            'ownerId': 'owner-1',
            'dashboardId': 'dashboard-1',
            'dashboardName': 'Studio controls',
          },
        ]),
      );
      await request.response.close();
    });
    addTearDown(subscription.cancel);

    final dataService = ShowRunnerDataService(directory);
    await dataService.savePluginSettings('twitch', {
      'accessToken': 'twitch-token',
    });
    await dataService.savePluginSettings('remote', {
      'apiBase': 'http://127.0.0.1:${server.port}',
    });

    final dashboards = await RemoteDashboardService(
      dataService: dataService,
    ).listAvailable();

    expect(dashboards.single.ownerId, 'owner-1');
    expect(dashboards.single.dashboardId, 'dashboard-1');
    expect(dashboards.single.name, 'Studio controls');
    expect(authorization, 'Bearer twitch-token');
    expect(requestUri?.path, '/api/dashboard-access/remote');
  });
}
