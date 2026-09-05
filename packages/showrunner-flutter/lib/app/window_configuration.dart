import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../schema/automation.dart';
import 'app_foundations.dart';

final class ShowRunnerWindowState {
  const ShowRunnerWindowState({
    required this.size,
    required this.position,
    required this.maximized,
  });

  final Size size;
  final Offset position;
  final bool maximized;

  factory ShowRunnerWindowState.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Window state must be an object.');
    }
    final json = Map<String, dynamic>.from(value);
    final width = _finiteNumber(json['width']);
    final height = _finiteNumber(json['height']);
    final x = _finiteNumber(json['x']);
    final y = _finiteNumber(json['y']);
    if (width == null ||
        height == null ||
        x == null ||
        y == null ||
        width < showRunnerMinimumWindowSize.width ||
        height < showRunnerMinimumWindowSize.height ||
        width > 10000 ||
        height > 10000) {
      throw const FormatException('Window state contains invalid bounds.');
    }
    return ShowRunnerWindowState(
      size: Size(width, height),
      position: Offset(x, y),
      maximized: json['maximized'] == true,
    );
  }

  JsonMap toJson() => {
    'width': size.width,
    'height': size.height,
    'x': position.dx,
    'y': position.dy,
    'maximized': maximized,
  };
}

Future<ShowRunnerWindowState?> loadShowRunnerWindowState(File file) async {
  if (!await file.exists()) return null;
  try {
    return ShowRunnerWindowState.fromJson(
      jsonDecode(await file.readAsString()),
    );
  } on Object {
    return null;
  }
}

Future<void> saveShowRunnerWindowState(File file) async {
  if (!Platform.isWindows) return;
  try {
    final state = ShowRunnerWindowState(
      size: await windowManager.getSize(),
      position: await windowManager.getPosition(),
      maximized: await windowManager.isMaximized(),
    );
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(state.toJson()));
    await temporary.rename(file.path);
  } on Object {
    // Window persistence must never prevent an orderly application close.
  }
}

Future<void> configureShowRunnerWindow({File? stateFile}) async {
  if (!Platform.isWindows) return;

  await windowManager.ensureInitialized();
  final saved = stateFile == null
      ? null
      : await loadShowRunnerWindowState(stateFile);
  const options = WindowOptions(
    size: showRunnerWindowSize,
    minimumSize: showRunnerMinimumWindowSize,
    center: false,
    title: 'ShowRunner',
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    if (saved != null) {
      await windowManager.setSize(saved.size);
      await windowManager.setPosition(saved.position);
    } else {
      await windowManager.center();
    }
    await windowManager.show();
    await windowManager.focus();
    if (saved?.maximized == true) await windowManager.maximize();
  });
}

double? _finiteNumber(Object? value) {
  final number = value is num ? value.toDouble() : double.tryParse('$value');
  return number != null && number.isFinite ? number : null;
}
