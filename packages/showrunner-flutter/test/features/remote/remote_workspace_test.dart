import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/remote/remote_workspace.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  test('discovers remote dashboards with the persisted Twitch token', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-remote-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final dataService = ShowRunnerDataService(directory);
    await dataService.savePluginSettings('twitch', {
      'accessToken': 'twitch-token',
    });

    String? receivedToken;
    final service = RemoteDashboardService(
      dataService: dataService,
      fetcher: (token) async {
        receivedToken = token;
        return const [
          RemoteDashboardInfo(
            ownerId: 'owner-1',
            dashboardId: 'dashboard-1',
            name: 'Studio controls',
          ),
        ];
      },
    );

    final dashboards = await service.listAvailable();

    expect(receivedToken, 'twitch-token');
    expect(dashboards.single.name, 'Studio controls');
    expect(dashboards.single.dashboardId, 'dashboard-1');
  });

  test('requires Twitch authentication before remote discovery', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-remote-',
    );
    addTearDown(() => directory.delete(recursive: true));

    final service = RemoteDashboardService(
      dataService: ShowRunnerDataService(directory),
      fetcher: (_) async => const [],
    );

    expect(service.listAvailable, throwsStateError);
  });

  test(
    'fetches and filters remote dashboards through the configured API',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'showrunner-remote-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requests = <HttpRequest>[];
      final subscription = server.listen((request) async {
        requests.add(request);
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode([
            {
              'ownerId': 'owner-1',
              'dashboardId': 'dashboard-1',
              'dashboardName': 'Studio controls',
            },
            {'ownerId': 'missing-dashboard-id'},
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

      expect(dashboards.map((dashboard) => dashboard.dashboardId), [
        'dashboard-1',
      ]);
      expect(
        requests.single.headers.value(HttpHeaders.authorizationHeader),
        'Bearer twitch-token',
      );
      expect(requests.single.uri.path, '/api/dashboard-access/remote');
    },
  );
}
