import 'dart:io';

import 'package:flutter/material.dart';
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
  if (setupCompleted) {
    await dataService.savePluginSettings('showrunner-flutter', const {
      'setupCompleted': true,
    });
  }
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
}) => MaterialApp(
  title: 'ShowRunner integration test',
  debugShowCheckedModeBanner: false,
  theme: buildShowRunnerTheme(),
  builder: showRunnerAppFrame,
  home: ShowRunnerPage(
    dataService: dataService,
    loadSampleGraph: loadSampleGraph,
    showGraphEditor: showGraphEditor,
    updateService: updateService,
  ),
);
