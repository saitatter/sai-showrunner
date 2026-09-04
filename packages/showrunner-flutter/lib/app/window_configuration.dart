import 'dart:io';

import 'package:window_manager/window_manager.dart';

import 'app_foundations.dart';

Future<void> configureShowRunnerWindow() async {
  if (!Platform.isWindows) return;

  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: showRunnerWindowSize,
    minimumSize: showRunnerMinimumWindowSize,
    center: true,
    title: 'ShowRunner',
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}
