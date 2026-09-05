import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/automation/automation_starters.dart';
import 'package:showrunner_flutter/plugins/overlays/manifest.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/runtime/automation_recovery.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/runtime/graph_runtime.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';

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
        'youtube-paid-alert',
        'twitch-sub-paid-alert',
        'twitch-bits-paid-alert',
        'starting-soon-scene-banner',
        'obs-scene-change',
        'twitch-chat-command-reply',
        'twitch-chat-moderation-review',
        'stream-plan-next-segment',
        'ending-scene-banner',
        'youtube-paid-event-alerts-queue',
        'paid-alert-queue-worker',
        'scene-begin-scene-queue',
        'scene-banner-queue-worker',
      ]),
    );
    for (final starter in starters) {
      expect(validateAutomationGraph(starter.automation), isEmpty);
      expect(starter.automation.graph.entryNodeId, isNotEmpty);
    }
  });

  test(
    'starter data wires and placeholders reach the real overlay action',
    () async {
      final eventHub = DartPluginEventHub();
      final registry = DartPluginRegistry()
        ..register(createOverlaysPlugin(eventHub: eventHub));
      addTearDown(registry.close);
      addTearDown(eventHub.dispose);
      final starter = defaultAutomationStarters().firstWhere(
        (item) => item.id == 'youtube-paid-alert',
      );
      final event = eventHub.stream(OverlayEventIds.broadcast).first;

      final result = await const DartGraphRuntime().executeWithRegistry(
        graph: starter.automation.graph,
        dataWires: starter.automation.dataWires,
        context: EvaluationContext(
          contextState: {
            'messageId': 'event-1',
            'viewerName': 'saita',
            'amountMicros': 2500,
            'currency': 'USD',
            'message': 'Thank you!',
          },
        ),
        registry: registry,
      );

      expect(result.completed, isTrue);
      expect(await event, {
        'broadcastId': 'showrunner_paid_alert',
        'payload': {
          'id': 'event-1',
          'targetOverlayId': '',
          'targetWidgetId': '',
          'platform': 'youtube',
          'displayName': 'saita',
          'amount': '2500',
          'currency': 'USD',
          'title': 'New Super Chat',
          'message': 'Thank you!',
        },
      });
    },
  );
}
