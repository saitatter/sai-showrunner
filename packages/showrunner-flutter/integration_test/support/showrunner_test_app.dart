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
  if (setupCompleted) {
    await ShowRunnerDataService(
      directory,
    ).savePluginSettings('showrunner-flutter', const {'setupCompleted': true});
  }
  return directory;
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
