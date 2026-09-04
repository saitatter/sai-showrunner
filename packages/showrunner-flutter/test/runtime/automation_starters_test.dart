import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/automation/automation_starters.dart';
import 'package:showrunner_flutter/runtime/automation_recovery.dart';

void main() {
  test('default automation starters are valid and uniquely identified', () {
    final starters = defaultAutomationStarters();
    expect(starters, isNotEmpty);
    expect(
      starters.map((starter) => starter.id).toSet(),
      hasLength(starters.length),
    );
    expect(
      starters.map((starter) => starter.id),
      containsAll(<String>[
        'chat-to-queue',
        'chat-overlay',
        'chat-queue-overlay',
        'paid-alert-to-queue',
        'scene-banner',
        'obs-scene-change',
      ]),
    );
    for (final starter in starters) {
      expect(validateAutomationGraph(starter.automation), isEmpty);
      expect(starter.automation.graph.entryNodeId, isNotEmpty);
    }
  });
}
