import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../schema/data_input.dart';
import '../../runtime/expression.dart';
import '../../runtime/graph_runtime.dart';
import '../../runtime/automation_queue_manager.dart';
import '../../schema/automation.dart';
import '../../schema/stream_plan.dart';
import '../registry/plugin_registry.dart';

final streamPlanRuntime = DartStreamPlanRuntime();

typedef DartStreamPlanComponentHandler =
    FutureOr<void> Function(String segmentId, dynamic config);

final class DartStreamPlanComponent {
  const DartStreamPlanComponent({
    required this.id,
    this.onActivate,
    this.onDeactivate,
    this.activeConfigChanged,
  });

  final String id;
  final DartStreamPlanComponentHandler? onActivate;
  final DartStreamPlanComponentHandler? onDeactivate;
  final DartStreamPlanComponentHandler? activeConfigChanged;
}

const _segmentSchema = DartDataInputSchema(
  label: 'Stream plan segment',
  kind: DartDataInputKind.object,
  // The reference actions have no user configuration. The optional fields
  // remain accepted by the handler for old Flutter-authored graphs, but are
  // intentionally not exposed as a new action contract.
  fields: [],
);

final class DartStreamPlanRuntime extends ChangeNotifier {
  DartStreamPlanRuntime({this.queueManager});

  DartAutomationQueueManager? queueManager;
  String? activePlanId;
  String? activeSegmentId;
  StreamPlanData? _activePlan;
  final Map<String, DartStreamPlanComponent> _componentTypes = {};
  Future<void>? _transition;

  StreamPlanData? get activePlan => _activePlan;
  bool get isActive => activePlanId != null;

  void registerComponentType(DartStreamPlanComponent component) {
    if (component.id.trim().isEmpty) {
      throw ArgumentError.value(component.id, 'component.id');
    }
    _componentTypes[component.id] = component;
  }

  DartStreamPlanComponent? componentType(String id) => _componentTypes[id];

  void activate(String planId, {String? segmentId}) {
    activePlanId = planId;
    activeSegmentId = segmentId;
    _activePlan = null;
    notifyListeners();
  }

  void deactivate() {
    activePlanId = null;
    activeSegmentId = null;
    _activePlan = null;
    notifyListeners();
  }

  String? next(StreamPlanData plan) {
    final index = plan.segments.indexWhere(
      (segment) => segment.id == activeSegmentId,
    );
    if (index < 0 || index + 1 >= plan.segments.length) return null;
    activeSegmentId = plan.segments[index + 1].id;
    notifyListeners();
    return activeSegmentId;
  }

  String? previous(StreamPlanData plan) {
    final index = plan.segments.indexWhere(
      (segment) => segment.id == activeSegmentId,
    );
    if (index <= 0) return null;
    activeSegmentId = plan.segments[index - 1].id;
    notifyListeners();
    return activeSegmentId;
  }

  Future<void> activatePlan(
    String planId,
    StreamPlanData plan, {
    required DartPluginRegistry registry,
    EvaluationContext? context,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
  }) => _exclusive(() async {
    if (activePlanId == planId && _activePlan != null) return;
    if (activePlanId != null) {
      await _deactivatePlanInternal(
        registry: registry,
        context: context,
        onNodeEnter: onNodeEnter,
        onNodeExit: onNodeExit,
      );
    }

    activePlanId = planId;
    activeSegmentId = null;
    _activePlan = plan;
    notifyListeners();
    await _runAutomation(
      plan.activationAutomation,
      planId: planId,
      sourceSubId: 'activation',
      registry: registry,
      context: context,
      onNodeEnter: onNodeEnter,
      onNodeExit: onNodeExit,
    );

    final firstSegment = plan.segments.firstOrNull;
    if (firstSegment != null) {
      await _activateSegmentInternal(
        planId,
        plan,
        firstSegment.id,
        registry: registry,
        context: context,
        onNodeEnter: onNodeEnter,
        onNodeExit: onNodeExit,
      );
    }
  });

  Future<void> deactivatePlan({
    required DartPluginRegistry registry,
    EvaluationContext? context,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
  }) => _exclusive(
    () => _deactivatePlanInternal(
      registry: registry,
      context: context,
      onNodeEnter: onNodeEnter,
      onNodeExit: onNodeExit,
    ),
  );

  Future<void> activatePlanSegment(
    String planId,
    StreamPlanData plan,
    String segmentId, {
    required DartPluginRegistry registry,
    EvaluationContext? context,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
  }) => _exclusive(
    () => _activateSegment(
      planId,
      plan,
      segmentId,
      registry: registry,
      context: context,
      onNodeEnter: onNodeEnter,
      onNodeExit: onNodeExit,
    ),
  );

  /// Refreshes the component configuration of the active segment without
  /// toggling the segment. This is used when an active Stream Plan resource
  /// is edited while it is running.
  Future<void> updateActivePlan(String planId, StreamPlanData plan) =>
      _exclusive(() async {
        if (activePlanId != planId || activeSegmentId == null) return;
        final segment = plan.segments
            .where((item) => item.id == activeSegmentId)
            .firstOrNull;
        if (segment == null) return;
        _activePlan = plan;
        notifyListeners();
        await _invokeActiveConfigChanged(segment);
      });

  Future<String?> transitionToNextSegment(
    String planId,
    StreamPlanData plan, {
    required DartPluginRegistry registry,
    EvaluationContext? context,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
  }) => _exclusive<String?>(() async {
    final target = _adjacentSegment(plan, forward: true);
    if (target == null) return null;
    await _activateSegment(
      planId,
      plan,
      target.id,
      registry: registry,
      context: context,
      onNodeEnter: onNodeEnter,
      onNodeExit: onNodeExit,
    );
    return target.id;
  });

  Future<String?> transitionToPreviousSegment(
    String planId,
    StreamPlanData plan, {
    required DartPluginRegistry registry,
    EvaluationContext? context,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
  }) => _exclusive<String?>(() async {
    final target = _adjacentSegment(plan, forward: false);
    if (target == null) return null;
    await _activateSegment(
      planId,
      plan,
      target.id,
      registry: registry,
      context: context,
      onNodeEnter: onNodeEnter,
      onNodeExit: onNodeExit,
    );
    return target.id;
  });

  Future<void> _activateSegment(
    String planId,
    StreamPlanData plan,
    String segmentId, {
    required DartPluginRegistry registry,
    EvaluationContext? context,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
  }) async {
    if (activePlanId != planId || _activePlan == null) {
      throw StateError('Stream Plan is not active: $planId');
    }
    final segment = plan.segments
        .where((item) => item.id == segmentId)
        .firstOrNull;
    if (segment == null) {
      throw StateError('Stream Plan segment was not found: $segmentId');
    }
    await _activateSegmentInternal(
      planId,
      plan,
      segment.id,
      registry: registry,
      context: context,
      onNodeEnter: onNodeEnter,
      onNodeExit: onNodeExit,
    );
  }

  Future<void> _activateSegmentInternal(
    String planId,
    StreamPlanData plan,
    String segmentId, {
    required DartPluginRegistry registry,
    EvaluationContext? context,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
  }) async {
    if (activeSegmentId != null) {
      await _deactivateSegmentInternal(
        planId,
        plan,
        activeSegmentId!,
        registry: registry,
        context: context,
        onNodeEnter: onNodeEnter,
        onNodeExit: onNodeExit,
      );
    }

    final segment = plan.segments.firstWhere((item) => item.id == segmentId);
    activeSegmentId = segment.id;
    notifyListeners();
    await _invokeComponentHandlers(segment, activate: true);
    await _runAutomation(
      segment.activationAutomation,
      planId: planId,
      segmentId: segment.id,
      sourceSubId: '${segment.id}.activation',
      registry: registry,
      context: context,
      onNodeEnter: onNodeEnter,
      onNodeExit: onNodeExit,
    );
  }

  Future<void> _deactivateSegmentInternal(
    String planId,
    StreamPlanData plan,
    String segmentId, {
    required DartPluginRegistry registry,
    EvaluationContext? context,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
  }) async {
    final segment = plan.segments
        .where((item) => item.id == segmentId)
        .firstOrNull;
    if (segment == null) return;
    await _invokeComponentHandlers(segment, activate: false);
    await _runAutomation(
      segment.deactivationAutomation,
      planId: planId,
      segmentId: segment.id,
      sourceSubId: '${segment.id}.deactivation',
      registry: registry,
      context: context,
      onNodeEnter: onNodeEnter,
      onNodeExit: onNodeExit,
    );
  }

  Future<void> _deactivatePlanInternal({
    required DartPluginRegistry registry,
    EvaluationContext? context,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
  }) async {
    final planId = activePlanId;
    final plan = _activePlan;
    if (planId == null || plan == null) {
      activePlanId = null;
      activeSegmentId = null;
      _activePlan = null;
      notifyListeners();
      return;
    }
    if (activeSegmentId != null) {
      await _deactivateSegmentInternal(
        planId,
        plan,
        activeSegmentId!,
        registry: registry,
        context: context,
        onNodeEnter: onNodeEnter,
        onNodeExit: onNodeExit,
      );
      activeSegmentId = null;
      notifyListeners();
    }
    await _runAutomation(
      plan.deactivationAutomation,
      planId: planId,
      sourceSubId: 'deactivation',
      registry: registry,
      context: context,
      onNodeEnter: onNodeEnter,
      onNodeExit: onNodeExit,
    );
    activePlanId = null;
    _activePlan = null;
    notifyListeners();
  }

  Future<void> _invokeComponentHandlers(
    StreamPlanSegmentData segment, {
    required bool activate,
  }) async {
    for (final entry in segment.components.entries) {
      final component = _componentTypes[entry.key];
      final handler = activate
          ? component?.onActivate
          : component?.onDeactivate;
      await handler?.call(segment.id, entry.value);
    }
  }

  Future<void> _invokeActiveConfigChanged(StreamPlanSegmentData segment) async {
    for (final entry in segment.components.entries) {
      await _componentTypes[entry.key]?.activeConfigChanged?.call(
        segment.id,
        entry.value,
      );
    }
  }

  Future<GraphExecutionResult> _runAutomation(
    JsonMap automation, {
    required String planId,
    String? segmentId,
    String? sourceSubId,
    required DartPluginRegistry registry,
    EvaluationContext? context,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
  }) async {
    final baseContext = context ?? EvaluationContext();
    final parsed = AutomationData.fromJson(automation);
    final executionContext = EvaluationContext(
      locals: Map<String, dynamic>.from(baseContext.locals),
      contextState: {
        ...baseContext.contextState,
        'streamPlan': {'planId': planId, 'segmentId': ?segmentId},
        'streamPlan.planId': planId,
        'streamPlan.segmentId': ?segmentId,
      },
      cancellationToken: baseContext.cancellationToken,
    );
    final queue = queueManager;
    final queueId = parsed.queueId;
    if (queue != null && queueId != null) {
      final item = await queue.enqueue(
        parsed,
        executionContext,
        queueId: queueId,
        sourceMetadata: {
          'sourceType': 'stream-plan',
          'sourceId': planId,
          ...?(sourceSubId == null
              ? null
              : <String, dynamic>{'sourceSubId': sourceSubId}),
        },
      );
      return GraphExecutionResult(
        completed: true,
        steps: 0,
        nodeResults: const <String, RuntimeMap>{},
        contextState: Map<String, dynamic>.from(executionContext.contextState),
        outputValues: {'queued': true, 'queueId': queueId, 'itemId': item.id},
      );
    }
    return const DartGraphRuntime().executeWithRegistry(
      graph: parsed.graph,
      context: executionContext,
      registry: registry,
      dataWires: parsed.dataWires,
      subgraphs: parsed.subgraphs,
      onNodeEnter: onNodeEnter,
      onNodeExit: onNodeExit,
    );
  }

  StreamPlanSegmentData? _adjacentSegment(
    StreamPlanData plan, {
    required bool forward,
  }) {
    final index = plan.segments.indexWhere(
      (segment) => segment.id == activeSegmentId,
    );
    final targetIndex = forward ? index + 1 : index - 1;
    if (index < 0 || targetIndex < 0 || targetIndex >= plan.segments.length) {
      return null;
    }
    return plan.segments[targetIndex];
  }

  Future<T> _exclusive<T>(Future<T> Function() operation) async {
    final previous = _transition;
    if (previous != null) {
      try {
        await previous;
      } catch (_) {
        // A failed transition must not permanently block later controls.
      }
    }
    final current = operation();
    final marker = current.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    _transition = marker;
    try {
      return await current;
    } finally {
      if (identical(_transition, marker)) _transition = null;
    }
  }
}

DartPluginManifest createStreamPlansPlugin({
  DartStreamPlanRuntime? runtime,
  DartPluginRegistry? registry,
  DartAutomationQueueManager? queueManager,
}) {
  final activeRuntime = runtime ?? streamPlanRuntime;
  if (queueManager != null) activeRuntime.queueManager = queueManager;
  return DartPluginManifest(
    id: 'stream-plans',
    name: 'Stream Plans',
    actions: [
      DartActionDefinition(
        pluginId: 'stream-plans',
        actionId: 'nextSegment',
        displayName: 'Next Segment',
        configSchema: _segmentSchema,
        invoke: (config, context) => _nextSegment(
          config,
          context,
          runtime: activeRuntime,
          registry: registry,
        ),
      ),
      DartActionDefinition(
        pluginId: 'stream-plans',
        actionId: 'prevSegment',
        displayName: 'Previous Segment',
        configSchema: _segmentSchema,
        invoke: (config, context) => _previousSegment(
          config,
          context,
          runtime: activeRuntime,
          registry: registry,
        ),
      ),
    ],
  );
}

Future<Object?> _nextSegment(
  RuntimeMap config,
  EvaluationContext context, {
  required DartStreamPlanRuntime runtime,
  DartPluginRegistry? registry,
}) async {
  final planId = config['planId']?.toString() ?? runtime.activePlanId;
  final segments = config['segments'];
  final segmentId =
      registry != null && planId != null && planId == runtime.activePlanId
      ? await runtime.transitionToNextSegment(
          planId,
          runtime.activePlan ??
              StreamPlanData.fromConfig({
                'segments': segments is List ? segments : const [],
              }),
          registry: registry,
          context: context,
        )
      : _move(runtime, config, forward: true);
  return {'planId': planId, 'segmentId': segmentId, 'action': 'nextSegment'};
}

Future<Object?> _previousSegment(
  RuntimeMap config,
  EvaluationContext context, {
  required DartStreamPlanRuntime runtime,
  DartPluginRegistry? registry,
}) async {
  final planId = config['planId']?.toString() ?? runtime.activePlanId;
  final segments = config['segments'];
  final segmentId =
      registry != null && planId != null && planId == runtime.activePlanId
      ? await runtime.transitionToPreviousSegment(
          planId,
          runtime.activePlan ??
              StreamPlanData.fromConfig({
                'segments': segments is List ? segments : const [],
              }),
          registry: registry,
          context: context,
        )
      : _move(runtime, config, forward: false);
  return {'planId': planId, 'segmentId': segmentId, 'action': 'prevSegment'};
}

String? _move(
  DartStreamPlanRuntime runtime,
  RuntimeMap config, {
  required bool forward,
}) {
  final segments = config['segments'];
  if (segments is! List) return config['segmentId']?.toString();
  final plan = StreamPlanData.fromConfig({'segments': segments});
  return forward ? runtime.next(plan) : runtime.previous(plan);
}
