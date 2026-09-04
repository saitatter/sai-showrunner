import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/stream_plans/manifest.dart';
import 'package:showrunner_flutter/schema/stream_plan.dart';

void main() {
  test('round-trips Stream Plan config with legacy defaults', () {
    final plan = StreamPlanData.fromConfig({
      'name': 'Friday show',
      'segments': [
        {
          'id': 'intro',
          'name': 'Intro',
          'components': {
            'twitch-stream-info': {
              'title': 'Welcome',
              'category': 'Just Chatting',
            },
          },
        },
      ],
    });

    expect(plan.name, 'Friday show');
    expect(plan.segments, hasLength(1));
    expect(plan.segments.single.activationAutomation['schemaVersion'], 2);
    expect(plan.segments.single.components['twitch-stream-info'], isNotNull);

    final restored = StreamPlanData.fromConfig(plan.toConfig());
    expect(restored.segments.single.id, 'intro');
    expect(restored.segments.single.name, 'Intro');
    expect(restored.segments.single.components['twitch-stream-info'], {
      'title': 'Welcome',
      'category': 'Just Chatting',
    });
  });

  test('moves the active plan between ordered segments', () {
    final plan = StreamPlanData(
      name: 'Show',
      activationAutomation: emptyInlineAutomation(),
      deactivationAutomation: emptyInlineAutomation(),
      segments: [_segment('one'), _segment('two'), _segment('three')],
    );
    final runtime = DartStreamPlanRuntime()
      ..activate('plan-1', segmentId: 'two');

    expect(runtime.next(plan), 'three');
    expect(runtime.previous(plan), 'two');
    expect(runtime.previous(plan), 'one');
    expect(runtime.previous(plan), isNull);
  });

  test('registers Stream Plan navigation actions', () async {
    final registry = DartPluginRegistry()..register(createStreamPlansPlugin());

    expect(registry.findAction('stream-plans', 'nextSegment'), isNotNull);
    expect(registry.findAction('stream-plans', 'prevSegment'), isNotNull);
    streamPlanRuntime.activate('plan-1', segmentId: 'one');
    const segments = [
      {'id': 'one', 'name': 'One'},
      {'id': 'two', 'name': 'Two'},
    ];
    final result = await registry.invokeAction('stream-plans', 'nextSegment', {
      'segments': segments,
    });
    expect((result as Map)['action'], 'nextSegment');
    expect(result['segmentId'], 'two');
    streamPlanRuntime.deactivate();
  });
}

StreamPlanSegmentData _segment(String id) => StreamPlanSegmentData(
  id: id,
  name: id,
  components: const {},
  activationAutomation: emptyInlineAutomation(),
  deactivationAutomation: emptyInlineAutomation(),
);
