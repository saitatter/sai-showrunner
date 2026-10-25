import 'dart:io';

import 'package:flutter/foundation.dart';

Directory showRunnerUserDirectory({
  Map<String, String>? environment,
  bool? release,
  bool portable = false,
  TargetPlatform? platform,
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
  final target = platform ?? defaultTargetPlatform;
  final home = values['HOME']?.trim();
  if (target == TargetPlatform.macOS && home?.isNotEmpty == true) {
    return Directory('$home/Library/Application Support/ShowRunner/user');
  }
  if (target == TargetPlatform.linux && home?.isNotEmpty == true) {
    final xdg = values['XDG_DATA_HOME']?.trim();
    final root = xdg?.startsWith('/') == true ? xdg! : '$home/.local/share';
    return Directory('$root/ShowRunner/user');
  }
  return Directory('user');
}
