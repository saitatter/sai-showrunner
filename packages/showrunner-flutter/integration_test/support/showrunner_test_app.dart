import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/app/application_controller.dart';
import 'package:showrunner_flutter/app/app_foundations.dart';
import 'package:showrunner_flutter/main.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';
import 'package:showrunner_flutter/services/update_check_service.dart';

Future<Directory> createShowRunnerFixtureDirectory({
  bool setupCompleted = true,
}) async {
  final directory = await Directory.systemTemp.createTemp(
    'showrunner-integration-',
  );
  final dataService = ShowRunnerDataService(directory);
  final httpPort = await _reserveLoopbackPort();
  await dataService.savePluginSettings('ShowRunner', {'port': httpPort});
  await dataService.savePluginSettings('showrunner-flutter', {
    'setupCompleted': setupCompleted,
    'disabledPlugins': ['obs', 'aitum', 'advss', 'input'],
  });
  await Directory('${directory.path}/state').create(recursive: true);
  return directory;
}

Future<int> _reserveLoopbackPort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Widget buildShowRunnerTestApp({
  required ShowRunnerDataService dataService,
  bool loadSampleGraph = false,
  bool showGraphEditor = true,
  UpdateCheckService? updateService,
}) {
  final application = ApplicationController.create(
    dataService: dataService,
    loadSampleGraph: loadSampleGraph,
    showGraphEditor: showGraphEditor,
  );
  // Registered after the fixture directory cleanup: teardown runs in reverse
  // order, so every owned read/write finishes before deleting isolated storage.
  addTearDown(application.shutdown);
  return MaterialApp(
    title: 'ShowRunner integration test',
    debugShowCheckedModeBanner: false,
    theme: buildShowRunnerTheme(),
    builder: showRunnerAppFrame,
    home: ShowRunnerPage(
      key: ObjectKey(application),
      application: application,
      dataService: dataService,
      loadSampleGraph: loadSampleGraph,
      showGraphEditor: showGraphEditor,
      updateService: updateService,
    ),
  );
}

Future<void> flushShowRunnerTestApp(WidgetTester tester) async {
  final applications = tester
      .widgetList<ShowRunnerPage>(find.byType(ShowRunnerPage))
      .map((page) => page.application!)
      .toList();
  expect(applications, isNotEmpty);
  await tester.runAsync(() async {
    for (final application in applications) {
      await application.start();
      await application.navigation.flush();
      await application.documents.flush();
    }
  });
}

Future<void> closeShowRunnerTestApp(WidgetTester tester) async {
  final applications = tester
      .widgetList<ShowRunnerPage>(find.byType(ShowRunnerPage))
      .map((page) => page.application!)
      .toList();
  expect(applications, isNotEmpty);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(
    () => Future.wait(applications.map((app) => app.shutdown())),
  );
  await tester.pump();
}
