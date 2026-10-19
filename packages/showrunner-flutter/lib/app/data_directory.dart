import 'dart:io';

import 'package:flutter/foundation.dart';

Directory showRunnerUserDirectory({
  Map<String, String>? environment,
  bool? release,
  bool portable = false,
}) {
  final values = environment ?? Platform.environment;
  final override = values['SHOWRUNNER_USER_DIR']?.trim();
  if (override?.isNotEmpty == true) return Directory(override!);

  if (portable || values['PORTABLE_EXECUTABLE_FILE']?.isNotEmpty == true) {
    final executableDirectory =
        values['PORTABLE_EXECUTABLE_DIR']?.trim() ?? Directory.current.path;
    return Directory('$executableDirectory${Platform.pathSeparator}user');
  }

  if (!(release ?? kReleaseMode)) return Directory('../../user');

  final appData = values['APPDATA']?.trim();
  if (appData?.isNotEmpty == true) {
    return Directory(
      '$appData${Platform.pathSeparator}ShowRunner${Platform.pathSeparator}user',
    );
  }
  final localAppData = values['LOCALAPPDATA']?.trim();
  if (localAppData?.isNotEmpty == true) {
    return Directory(
      '$localAppData${Platform.pathSeparator}ShowRunner${Platform.pathSeparator}user',
    );
  }
  return Directory('user');
}
