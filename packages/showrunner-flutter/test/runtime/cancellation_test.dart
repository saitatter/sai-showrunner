import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/runtime/cancellation.dart';

void main() {
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
