import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/time/manifest.dart';
import 'package:showrunner_flutter/runtime/cancellation.dart';
import 'package:showrunner_flutter/runtime/expression.dart';

void main() {
  test('delay observes graph cancellation', () async {
    final token = DartCancellationToken(id: 'time-cancel');
    final action = createTimePlugin().actions.firstWhere(
      (action) => action.actionId == 'delay',
    );
    final execution = action.invoke({
      'duration': 10,
    }, EvaluationContext(cancellationToken: token));
    final expectedCancellation = expectLater(
      execution,
      throwsA(isA<DartCancelledException>()),
    );
    await Future<void>.delayed(Duration.zero);
    token.cancel();

    await expectedCancellation;
  });
}
