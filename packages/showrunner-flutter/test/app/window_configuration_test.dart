import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/app/app_foundations.dart';
import 'package:showrunner_flutter/app/window_configuration.dart';

void main() {
  test('round-trips a valid window snapshot', () {
    const state = ShowRunnerWindowState(
      size: Size(1440, 900),
      position: Offset(20, 30),
      maximized: true,
    );

    final restored = ShowRunnerWindowState.fromJson(state.toJson());

    expect(restored.size, state.size);
    expect(restored.position, state.position);
    expect(restored.maximized, isTrue);
  });

  test('ignores malformed or undersized window snapshots', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-window-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/window.json');
    await file.writeAsString(
      jsonEncode({
        'width': showRunnerMinimumWindowSize.width - 1,
        'height': showRunnerMinimumWindowSize.height,
        'x': 0,
        'y': 0,
        'maximized': false,
      }),
    );

    expect(await loadShowRunnerWindowState(file), isNull);
  });

  test('returns null when the window snapshot does not exist', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-window-',
    );
    addTearDown(() => directory.delete(recursive: true));

    expect(
      await loadShowRunnerWindowState(File('${directory.path}/missing.json')),
      isNull,
    );
  });
}
