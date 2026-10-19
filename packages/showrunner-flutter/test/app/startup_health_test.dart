import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/app/startup_health.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

void main() {
  test('classifies startup health as ready or offline', () async {
    final readyDirectory = await Directory.systemTemp.createTemp(
      'showrunner-ready-',
    );
    addTearDown(() => readyDirectory.delete(recursive: true));
    await Directory('${readyDirectory.path}/settings').create();
    await Directory('${readyDirectory.path}/state').create();

    final ready = await StartupHealthLoader(
      ShowRunnerDataService(readyDirectory),
    ).load();
    expect(ready.state, StartupHealthState.ready);

    final offlineDirectory = await Directory.systemTemp.createTemp(
      'showrunner-offline-',
    );
    addTearDown(() => offlineDirectory.delete(recursive: true));
    final offline = await StartupHealthLoader(
      ShowRunnerDataService(offlineDirectory),
    ).load();
    expect(offline.state, StartupHealthState.offline);
  });
}
