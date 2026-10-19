import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/app/data_directory.dart';

void main() {
  test('honors the explicit data directory override', () {
    final directory = showRunnerUserDirectory(
      environment: {'SHOWRUNNER_USER_DIR': r'C:\smoke-user'},
      release: true,
    );

    expect(directory.path, r'C:\smoke-user');
  });

  test('keeps the repository-relative data directory in debug', () {
    final directory = showRunnerUserDirectory(
      environment: const {},
      release: false,
    );

    expect(directory.path, '../../user');
  });

  test('uses the executable directory for portable release mode', () {
    final directory = showRunnerUserDirectory(
      environment: {'PORTABLE_EXECUTABLE_DIR': r'C:\ShowRunner'},
      release: true,
      portable: true,
    );

    expect(
      directory.path,
      'C:${Platform.pathSeparator}ShowRunner${Platform.pathSeparator}user',
    );
  });

  test('uses the Windows app data directory for packaged release mode', () {
    final directory = showRunnerUserDirectory(
      environment: {'APPDATA': r'C:\Users\saita\AppData\Roaming'},
      release: true,
    );

    expect(
      directory.path,
      'C:${Platform.pathSeparator}Users${Platform.pathSeparator}saita'
      '${Platform.pathSeparator}AppData${Platform.pathSeparator}Roaming'
      '${Platform.pathSeparator}ShowRunner${Platform.pathSeparator}user',
    );
  });
}
