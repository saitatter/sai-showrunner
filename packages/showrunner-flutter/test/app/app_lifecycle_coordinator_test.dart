import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/app/lifecycle/app_lifecycle_coordinator.dart';

void main() {
  test(
    'runs shutdown tasks once in order and continues after failure',
    () async {
      final calls = <String>[];
      final coordinator = AppLifecycleCoordinator(
        shutdownTasks: [
          () async => calls.add('provider'),
          () async {
            calls.add('plugin');
            throw StateError('plugin stop failed');
          },
          () async => calls.add('lock'),
        ],
      );

      await expectLater(coordinator.shutdown(), throwsStateError);
      await expectLater(coordinator.shutdown(), throwsStateError);
      expect(calls, ['provider', 'plugin', 'lock']);
      expect(coordinator.isShuttingDown, isTrue);
    },
  );
}
