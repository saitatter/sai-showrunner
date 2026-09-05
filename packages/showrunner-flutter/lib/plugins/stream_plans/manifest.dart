import '../../runtime/expression.dart';
import '../../components/data_inputs/data_input.dart';
import '../../schema/stream_plan.dart';
import '../registry/plugin_registry.dart';

final streamPlanRuntime = DartStreamPlanRuntime();

const _segmentSchema = DartDataInputSchema(
  label: 'Stream plan segment',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Plan ID',
      key: 'planId',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      label: 'Segment ID',
      key: 'segmentId',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      label: 'Segments (JSON)',
      key: 'segments',
      kind: DartDataInputKind.array,
      itemKind: DartDataInputKind.object,
    ),
  ],
);

final class DartStreamPlanRuntime {
  String? activePlanId;
  String? activeSegmentId;

  void activate(String planId, {String? segmentId}) {
    activePlanId = planId;
    activeSegmentId = segmentId;
  }

  void deactivate() {
    activePlanId = null;
    activeSegmentId = null;
  }

  String? next(StreamPlanData plan) {
    final index = plan.segments.indexWhere(
      (segment) => segment.id == activeSegmentId,
    );
    if (index < 0 || index + 1 >= plan.segments.length) return null;
    activeSegmentId = plan.segments[index + 1].id;
    return activeSegmentId;
  }

  String? previous(StreamPlanData plan) {
    final index = plan.segments.indexWhere(
      (segment) => segment.id == activeSegmentId,
    );
    if (index <= 0) return null;
    activeSegmentId = plan.segments[index - 1].id;
    return activeSegmentId;
  }
}

DartPluginManifest createStreamPlansPlugin() => DartPluginManifest(
  id: 'stream-plans',
  name: 'Stream Plans',
  actions: [
    DartActionDefinition(
      pluginId: 'stream-plans',
      actionId: 'nextSegment',
      displayName: 'Next Segment',
      configSchema: _segmentSchema,
      invoke: _nextSegment,
    ),
    DartActionDefinition(
      pluginId: 'stream-plans',
      actionId: 'prevSegment',
      displayName: 'Previous Segment',
      configSchema: _segmentSchema,
      invoke: _previousSegment,
    ),
  ],
);

Future<Object?> _nextSegment(
  RuntimeMap config,
  EvaluationContext context,
) async => {
  'planId': config['planId'] ?? streamPlanRuntime.activePlanId,
  'segmentId': _move(config, forward: true),
  'action': 'nextSegment',
};

Future<Object?> _previousSegment(
  RuntimeMap config,
  EvaluationContext context,
) async => {
  'planId': config['planId'] ?? streamPlanRuntime.activePlanId,
  'segmentId': _move(config, forward: false),
  'action': 'prevSegment',
};

String? _move(RuntimeMap config, {required bool forward}) {
  final segments = config['segments'];
  if (segments is! List) return config['segmentId']?.toString();
  final plan = StreamPlanData.fromConfig({'segments': segments});
  return forward
      ? streamPlanRuntime.next(plan)
      : streamPlanRuntime.previous(plan);
}
