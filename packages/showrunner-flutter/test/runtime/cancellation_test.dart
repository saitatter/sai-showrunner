import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/runtime/cancellation.dart';

void main() {
  test(
    'physical aborts run before synchronous cancellation continuations',
    () async {
      final token = DartCancellationToken();
      final order = <String>[];
      void abort() {
        order.add('abort');
      }

      token.addListener(() {
        throw StateError('failed abort');
      });
      token.addListener(abort);
      final waiting = token.whenCancelled.then((_) {
        token.removeListener(abort);
        order.add('continuation');
      });
      token.cancel();
      token.cancel();
      await waiting;
      expect(order, ['abort', 'continuation']);
    },
  );
  test(
    'notifies listeners and supports listeners added after cancellation',
    () {
      final token = DartCancellationToken(id: 'test-cancel');
      var calls = 0;

      token.addListener(() => calls++);
      token.cancel();
      token.addListener(() => calls++);

      expect(token.isCancelled, isTrue);
      expect(calls, 2);
      expect(
        () => token.throwIfCancelled(),
        throwsA(isA<DartCancelledException>()),
      );
    },
  );
}
