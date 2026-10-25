import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'services/structured_logger.dart';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app/app_foundations.dart';
import 'app/data_directory.dart';
import 'app/single_instance_lock.dart';
import 'app/window_configuration.dart';
import 'services/showrunner_data_service.dart';
import 'services/update_check_service.dart';

import 'app/showrunner_page.dart';
export 'app/showrunner_page.dart' show ShowRunnerPage;

Future<void> main(List<String> args) async {
  final smokeMode = args.any((arg) => arg.startsWith('--showrunner-smoke='));
  void progress(String stage) {
    if (smokeMode) stdout.writeln('Flutter smoke bootstrap: $stage');
  }

  WidgetsFlutterBinding.ensureInitialized();
  progress('binding ready');
  MediaKit.ensureInitialized();
  progress('media ready');
  final portable = args.contains('--portable');
  final userDirectory = showRunnerUserDirectory(portable: portable);
  await ShowRunnerLogger.instance.initialize(
    Directory('${userDirectory.path}/logs'),
  );
  FlutterError.onError = (details) {
    ShowRunnerLogger.instance.error(
      'flutter',
      'Flutter framework error',
      error: details.exception,
      stackTrace: details.stack,
    );
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    ShowRunnerLogger.instance.error(
      'application',
      'Unhandled asynchronous error',
      error: error,
      stackTrace: stackTrace,
    );
    return true;
  };
  final instanceLock = await SingleInstanceLock.acquire(userDirectory);
  if (instanceLock == null) {
    stderr.writeln(
      'ShowRunner is already running for this user directory: '
      '${userDirectory.path}',
    );
    return;
  }
  progress('instance lock ready; configuring window');
  try {
    await configureShowRunnerWindow(
      stateFile: File('${userDirectory.path}/state/window.json'),
    );
  } on Object {
    await instanceLock.release();
    rethrow;
  }
  progress('window ready; launching application');
  final smokeArgument = args.cast<String?>().firstWhere(
    (argument) => argument?.startsWith('--showrunner-smoke=') == true,
    orElse: () => null,
  );
  runApp(
    ShowRunnerFlutterApp(
      smokeScenario: smokeArgument?.split('=').last,
      portable: portable,
      userDirectory: userDirectory,
      instanceLock: instanceLock,
    ),
  );
}

class ShowRunnerFlutterApp extends StatelessWidget {
  const ShowRunnerFlutterApp({
    super.key,
    this.smokeScenario,
    this.portable = false,
    this.userDirectory,
    this.instanceLock,
  });

  final String? smokeScenario;
  final bool portable;
  final Directory? userDirectory;
  final SingleInstanceLock? instanceLock;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShowRunner',
      debugShowCheckedModeBanner: false,
      theme: buildShowRunnerTheme(),
      builder: showRunnerAppFrame,
      home: ShowRunnerPage(
        dataService: ShowRunnerDataService(
          userDirectory ?? showRunnerUserDirectory(portable: portable),
        ),
        updateService: UpdateCheckService(
          currentVersion: showRunnerFlutterVersion,
        ),
        smokeScenario: smokeScenario,
        instanceLock: instanceLock,
      ),
    );
  }
}
