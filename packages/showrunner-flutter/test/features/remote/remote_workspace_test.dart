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
}
