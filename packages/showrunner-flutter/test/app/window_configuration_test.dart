import 'dart:async';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/app/app_foundations.dart';
import 'package:showrunner_flutter/app/window_configuration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final fails in [false, true]) {
    test(
      'window configuration owns pending focus and its failure: $fails',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'window-setup-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = File('${directory.path}/window.json');
        await file.writeAsString(
          jsonEncode(
            const ShowRunnerWindowState(
              size: Size(1440, 900),
              position: Offset(10, 20),
              maximized: false,
            ).toJson(),
          ),
        );
        const channel = MethodChannel('window_manager');
        final entered = Completer<void>(), focus = Completer<void>();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'focus') {
                entered.complete();
                await focus.future;
              }
              if (call.method.startsWith('is')) return false;
              if (call.method == 'getBounds') {
                return {'x': 0.0, 'y': 0.0, 'width': 1440.0, 'height': 900.0};
              }
              return null;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        var completed = false;
        final configured = configureShowRunnerWindow(stateFile: file)
            .then<Object?>(
              (_) {
                completed = true;
                return null;
              },
              onError: (Object error) {
                completed = true;
                return error;
              },
            );
        await entered.future;
        await Future<void>.delayed(Duration.zero);
        expect(completed, isFalse);
        if (fails) {
          focus.completeError(PlatformException(code: 'fixture-focus'));
        } else {
          focus.complete();
        }
        expect(await configured, fails ? isA<PlatformException>() : isNull);
      },
    );
  }
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
