import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/app/showrunner_tray.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'dispose waits for tray initialization and destroys the owned icon once',
    () async {
      const channel = MethodChannel('tray_manager');
      final entered = Completer<void>(), release = Completer<void>();
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'setIcon') {
              entered.complete();
              await release.future;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final tray = ShowRunnerTrayController(
        onShowRequested: () async {},
        onExitRequested: () async {},
      );
      final starting = tray.initialize();
      await entered.future;
      final stopping = tray.dispose();
      expect(calls, ['setIcon']);
      release.complete();
      await Future.wait([starting, stopping, tray.dispose()]);
      expect(calls.last, 'destroy');
      expect(calls.where((call) => call == 'destroy'), hasLength(1));
      await expectLater(tray.initialize(), throwsStateError);
    },
    skip: !Platform.isWindows,
  );
}
