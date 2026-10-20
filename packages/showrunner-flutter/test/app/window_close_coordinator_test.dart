import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/app/lifecycle/window_close_coordinator.dart';
import 'package:showrunner_flutter/features/settings/interface_preferences.dart';

void main() {
  test(
    'shutdown deadline reports failure without closing or cancelling teardown',
    () async {
      final stopped = Completer<void>();
      var closes = 0;
      final coordinator = WindowCloseCoordinator(
        behavior: () => WindowCloseBehavior.alwaysClose,
        ask: () async => WindowCloseChoice.close,
        hide: () async => false,
        confirmDocuments: () async => true,
        confirmProfile: () async => true,
        saveWindow: () async {},
        shutdown: () => stopped.future,
        closeWindow: () async {
          closes++;
        },
        shutdownTimeout: Duration.zero,
      );
      await expectLater(
        coordinator.request(),
        throwsA(isA<TimeoutException>()),
      );
      expect(closes, 0);
      expect(coordinator.isInProgress, false);
      stopped.complete();
      expect(await coordinator.request(), true);
      expect(closes, 1);
    },
  );
  for (final cancelDocuments in [true, false]) {
    test(
      'a cancelled ${cancelDocuments ? 'document' : 'profile'} guard never shuts down',
      () async {
        final events = <String>[];
        final coordinator = WindowCloseCoordinator(
          behavior: () => WindowCloseBehavior.alwaysClose,
          ask: () async => WindowCloseChoice.close,
          hide: () async => false,
          confirmDocuments: () async => !cancelDocuments,
          confirmProfile: () async => cancelDocuments,
          saveWindow: () async => events.add('save'),
          shutdown: () async => events.add('shutdown'),
          closeWindow: () async => events.add('close'),
        );
        expect(await coordinator.request(), false);
        expect(events, isEmpty);
      },
    );
  }
  test(
    'native close awaits owned teardown and ignores duplicate close requests',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final events = <String>[];
      final coordinator = WindowCloseCoordinator(
        behavior: () => WindowCloseBehavior.alwaysClose,
        ask: () async => WindowCloseChoice.close,
        hide: () async => false,
        confirmDocuments: () async => true,
        confirmProfile: () async => true,
        saveWindow: () async => events.add('save'),
        shutdown: () async {
          entered.complete();
          await release.future;
          events.add('stopped');
        },
        closeWindow: () async => events.add('close'),
      );
      final close = coordinator.request();
      await entered.future;
      expect(await coordinator.request(), false);
      expect(events, ['save']);
      release.complete();
      expect(await close, true);
      expect(await coordinator.request(), true);
      expect(events, ['save', 'stopped', 'close']);
    },
  );
  test(
    'tray hide keeps runtime running; forced exit still checks dirty guards',
    () async {
      var checks = 0, stops = 0;
      final coordinator = WindowCloseCoordinator(
        behavior: () => WindowCloseBehavior.hideToTray,
        ask: () async => WindowCloseChoice.close,
        hide: () async => true,
        confirmDocuments: () async {
          checks++;
          return false;
        },
        confirmProfile: () async => true,
        saveWindow: () async {},
        shutdown: () async {
          stops++;
        },
        closeWindow: () async {},
      );
      expect(await coordinator.request(), false);
      expect(checks, 0);
      expect(await coordinator.request(forceClose: true), false);
      expect(checks, 1);
      expect(stops, 0);
    },
  );
}
