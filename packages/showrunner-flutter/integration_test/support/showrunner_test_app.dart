import 'dart:io';

import 'package:flutter/material.dart';
import 'package:showrunner_flutter/app/app_foundations.dart';
import 'package:showrunner_flutter/main.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';

Future<Directory> createShowRunnerFixtureDirectory() async {
  final directory = await Directory.systemTemp.createTemp(
    'showrunner-integration-',
  );
  await ShowRunnerDataService(
    directory,
  ).savePluginSettings('showrunner-flutter', const {'setupCompleted': true});
  return directory;
}

Widget buildShowRunnerTestApp({
  required ShowRunnerDataService dataService,
  bool showGraphEditor = true,
}) => MaterialApp(
  title: 'ShowRunner integration test',
  debugShowCheckedModeBanner: false,
  theme: buildShowRunnerTheme(),
  builder: showRunnerAppFrame,
  home: ShowRunnerPage(
    dataService: dataService,
    loadSampleGraph: false,
    showGraphEditor: showGraphEditor,
  ),
);
