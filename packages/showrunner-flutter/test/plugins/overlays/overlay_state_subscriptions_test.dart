import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/overlays/overlay_state_subscriptions.dart';

void main() {
  test(
    'measured fanout skips unchanged snapshots and sends only the changed state',
    () async {
      var sent = 0;
      final service = OverlayStateSubscriptionService<String>(
        send: (_, _, _, _) async {
          sent++;
        },
        onFailure: (_) async {},
      );
      await Future.wait([
        for (final peer in ['first', 'second'])
          for (var state = 0; state < 64; state++)
            service.update(peer, 'probe', 'state$state', 0, force: true),
      ]);
      expect(sent, 128);
      for (var notification = 0; notification < 10; notification++) {
        await Future.wait([
          for (final peer in ['first', 'second'])
            for (var state = 0; state < 64; state++)
              service.update(peer, 'probe', 'state$state', 0),
        ]);
      }
      expect(
        sent,
        128,
        reason: 'The old broadcast loop sent another 1280 messages here.',
      );
      await Future.wait([
        for (final peer in ['first', 'second'])
          service.update(peer, 'probe', 'state7', 1),
      ]);
      expect(sent, 130);
      await service.close();
    },
  );

  test(
    'backpressure coalesces one state to its latest value without overlapping sends',
    () async {
      final gate = Completer<void>();
      final values = <Object?>[];
      var active = 0, peak = 0;
      final service = OverlayStateSubscriptionService<String>(
        send: (_, _, _, value) async {
          active++;
          if (active > peak) peak = active;
          values.add(value);
          if (values.length == 1) await gate.future;
          active--;
        },
        onFailure: (_) async {},
      );
      final first = service.update('peer', 'probe', 'value', 0);
      Future<void>? latest;
      for (var value = 1; value <= 100; value++) {
        latest = service.update('peer', 'probe', 'value', value);
      }
      gate.complete();
      await first;
      await latest;
      expect(values, [0, 100]);
      expect(peak, 1);
      await service.close();
    },
  );

  test(
    'forced reacquisition resends unchanged data and released states lose cached delivery',
    () async {
      var sent = 0;
      final service = OverlayStateSubscriptionService<String>(
        send: (_, _, _, _) async {
          sent++;
        },
        onFailure: (_) async {},
      );
      await service.update('peer', 'probe', 'value', 10);
      await service.update('peer', 'probe', 'value', 10, force: true);
      expect(sent, 2);
      service.forget('peer', 'probe\u0000value');
      await service.update('peer', 'probe', 'value', 10);
      expect(sent, 3);
      await service.close();
    },
  );

  test(
    'close settles queued promises and waits for its in-flight send',
    () async {
      final gate = Completer<void>();
      final values = <Object?>[];
      final service = OverlayStateSubscriptionService<String>(
        send: (_, _, _, value) async {
          values.add(value);
          await gate.future;
        },
        onFailure: (_) async {},
      );
      final first = service.update('peer', 'probe', 'one', 1);
      final second = service.update('peer', 'probe', 'two', 2);
      final checked = [
        expectLater(first, throwsStateError),
        expectLater(second, throwsStateError),
      ];
      final closing = service.close();
      await Future.wait(checked);
      gate.complete();
      await closing;
      expect(values, [1]);
      await expectLater(
        service.update('peer', 'probe', 'late', 3),
        throwsStateError,
      );
    },
  );
}
