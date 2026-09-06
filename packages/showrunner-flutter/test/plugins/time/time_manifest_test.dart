import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/time/manifest.dart';
import 'package:showrunner_flutter/plugins/variables/manifest.dart';
import 'package:showrunner_flutter/plugins/variables/runtime.dart';
import 'package:showrunner_flutter/runtime/cancellation.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/schema/resource.dart';

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

  test('timer actions operate on persisted Timer variables', () async {
    final root = await Directory.systemTemp.createTemp('showrunner-timers-');
    addTearDown(() => root.delete(recursive: true));
    final directory = Directory('${root.path}/variables');
    await ResourceRepository(directory).save(
      const ResourceData(
        id: 'showTimer',
        config: {
          'name': 'showTimer',
          'type': 'Timer',
          'defaultValue': {'remainingTime': 0},
          'persistent': true,
        },
        state: {
          'value': {'remainingTime': 0},
        },
      ),
    );

    final registry = DartPluginRegistry();
    final runtime = DartVariableRuntime(
      directory: directory,
      onChanged: (id, value) =>
          registry.updateDynamicState('variables', id, value),
    );
    registry.register(createTimePlugin(variableRuntime: runtime));
    registry.register(createVariablesPlugin(variableRuntime: runtime));
    addTearDown(registry.close);
    await registry.start();

    await registry.invokeAction('time', 'setTimer', {
      'timer': 'showTimer',
      'duration': 12,
    });
    expect((runtime.valueOf('showTimer') as Map)['remainingTime'], 12);

    final toggle = await registry.invokeAction('time', 'toggleTimer', {
      'timer': 'showTimer',
      'on': true,
    });
    final running = runtime.valueOf('showTimer') as Map;
    expect((toggle as Map)['timerRunning'], isTrue);
    expect(running['endTime'], isA<num>());
  });
}
