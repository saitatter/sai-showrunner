import '../../runtime/cancellation.dart';
import '../../runtime/automation_invocation_service.dart';
import '../../runtime/graph_invocation.dart';
import '../../graph/domain/automation_document.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../schema/data_input.dart';
import '../../runtime/expression.dart';
import '../../graph/runtime/graph_execution_engine.dart';
import '../../runtime/automation_queue_manager.dart';
import '../../schema/json.dart';
import '../../schema/stream_plan.dart';
import 'resources.dart';
import '../registry/plugin_registry.dart';
import 'contracts.dart';

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

final class StreamPlanCleanupFailure implements Exception {
  StreamPlanCleanupFailure(this.cause, Iterable<Object> cleanupErrors)
    : cleanupErrors = List.unmodifiable(cleanupErrors);
  final Object cause;
  final List<Object> cleanupErrors;
  @override
  String toString() =>
      'Stream Plan transition failed and component cleanup also failed.';
}

final class DartStreamPlanRuntime extends ChangeNotifier {
  DartStreamPlanRuntime({
    this.queueManager,
    GraphExecutionEngine? executionEngine,
  }) : executionEngine = executionEngine ?? CompiledExecutionEngine();

  DartAutomationQueueManager? queueManager;
  GraphExecutionEngine executionEngine;
  String? activePlanId;
  String? activeSegmentId;
  StreamPlanData? _activePlan;
  final Map<String, DartStreamPlanComponent> _componentTypes = {};
  Future<void>? _transition;
  Object? lastTransitionError;
  final Set<DartCancellationToken> _runTokens = {};
  bool _cleanupDuringClose = false;

  Future<void>? _closing;
  bool _closed = false;
  Future<void> close({DartPluginRegistry? registry}) {
    final pending = _closing;
    if (pending != null) return pending;
    final completion = Completer<void>();
    _closing = completion.future;
    unawaited(
      _close(registry).then<void>(
        completion.complete,
        onError: (Object error, StackTrace stack) =>
            completion.completeError(error, stack),
      ),
    );
    return completion.future;
  }

  Future<void> _close(DartPluginRegistry? registry) async {
    for (final token in _runTokens.toList()) {
      token.cancel();
    }
    try {
      await _transition;
      _cleanupDuringClose = true;
      if (isActive && registry != null) {
        await _deactivatePlanInternal(registry: registry);
      }
    } finally {
      _cleanupDuringClose = false;
      activePlanId = null;
      activeSegmentId = null;
      _activePlan = null;
      _componentTypes.clear();
      _closed = true;
      super.dispose();
    }
  }

  @override
  void notifyListeners() {
    if (!_closed) super.notifyListeners();
  }

  void _ensureOpen() {
    if (_closed || _closing != null) {
      throw StateError('Stream Plan runtime is closed.');
    }
  }

  StreamPlanData? get activePlan => _activePlan;
  bool get isActive => activePlanId != null;

  void registerComponentType(DartStreamPlanComponent component) {
    _ensureOpen();
    if (component.id.trim().isEmpty) {
      throw ArgumentError.value(component.id, 'component.id');
    }
    _componentTypes[component.id] = component;
  }

  DartStreamPlanComponent? componentType(String id) => _componentTypes[id];

  void activate(String planId, {String? segmentId}) {
    _ensureOpen();
    activePlanId = planId;
    activeSegmentId = segmentId;
    _activePlan = null;
    notifyListeners();
  }

  void deactivate() {
    _ensureOpen();
    activePlanId = null;
    activeSegmentId = null;
    _activePlan = null;
    notifyListeners();
  }

  String? next(StreamPlanData plan) {
    _ensureOpen();
    final index = plan.segments.indexWhere(
      (segment) => segment.id == activeSegmentId,
    );
    if (index < 0 || index + 1 >= plan.segments.length) return null;
    activeSegmentId = plan.segments[index + 1].id;
    notifyListeners();
    return activeSegmentId;
  }

  String? previous(StreamPlanData plan) {
    _ensureOpen();
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
    try {
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
    } catch (_) {
      activePlanId = null;
      activeSegmentId = null;
      _activePlan = null;
      notifyListeners();
      rethrow;
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
        final previous = _activePlan?.segments
            .where((item) => item.id == activeSegmentId)
            .firstOrNull;
        _activePlan = plan;
        notifyListeners();
        for (final entry in (previous?.components ?? {}).entries) {
          if (!segment.components.containsKey(entry.key)) {
            await _componentTypes[entry.key]?.onDeactivate?.call(
              segment.id,
              entry.value,
            );
          }
        }
        for (final entry in segment.components.entries) {
          final component = _componentTypes[entry.key];
          final handler = previous?.components.containsKey(entry.key) == true
              ? component?.activeConfigChanged
              : component?.onActivate;
          await handler?.call(segment.id, entry.value);
        }
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
      try {
        await _deactivateSegmentInternal(
          planId,
          plan,
          activeSegmentId!,
          registry: registry,
          context: context,
          onNodeEnter: onNodeEnter,
          onNodeExit: onNodeExit,
        );
      } finally {
        activeSegmentId = null;
        notifyListeners();
      }
    }

    final segment = plan.segments.firstWhere((item) => item.id == segmentId);
    activeSegmentId = segment.id;
    notifyListeners();
    final reached = <({DartStreamPlanComponent? component, dynamic config})>[];
    try {
      for (final entry in segment.components.entries) {
        final component = _componentTypes[entry.key];
        reached.add((component: component, config: entry.value));
        await component?.onActivate?.call(segment.id, entry.value);
      }
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
    } catch (error, stack) {
      final failures = <Object>[];
      for (final entry in reached.reversed) {
        try {
          await entry.component?.onDeactivate?.call(segment.id, entry.config);
        } catch (cleanup) {
          failures.add(cleanup);
        }
      }
      activeSegmentId = null;
      notifyListeners();
      if (failures.isNotEmpty) throw StreamPlanCleanupFailure(error, failures);
      Error.throwWithStackTrace(error, stack);
    }
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
    Object? failure;
    StackTrace? failureStack;
    for (final entry in segment.components.entries) {
      try {
        await _componentTypes[entry.key]?.onDeactivate?.call(
          segment.id,
          entry.value,
        );
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }
    try {
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
    } catch (error, stack) {
      failure ??= error;
      failureStack ??= stack;
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
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
    Object? failure;
    StackTrace? failureStack;
    if (activeSegmentId != null) {
      try {
        await _deactivateSegmentInternal(
          planId,
          plan,
          activeSegmentId!,
          registry: registry,
          context: context,
          onNodeEnter: onNodeEnter,
          onNodeExit: onNodeExit,
        );
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
      activeSegmentId = null;
      notifyListeners();
    }
    try {
      await _runAutomation(
        plan.deactivationAutomation,
        planId: planId,
        sourceSubId: 'deactivation',
        registry: registry,
        context: context,
        onNodeEnter: onNodeEnter,
        onNodeExit: onNodeExit,
      );
    } catch (error, stack) {
      failure ??= error;
      failureStack ??= stack;
    }
    activePlanId = null;
    _activePlan = null;
    notifyListeners();
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
  }

  Future<InvocationResult> _runAutomation(
    JsonMap automation, {
    required String planId,
    String? segmentId,
    String? sourceSubId,
    required DartPluginRegistry registry,
    EvaluationContext? context,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
  }) async {
    if (_closed || (_closing != null && !_cleanupDuringClose)) {
      throw StateError('Stream Plan runtime is closed.');
    }
    final baseContext = context ?? EvaluationContext();
    final parsed = AutomationDocument.fromJson(automation);
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
    final token = DartCancellationToken();
    final parent = executionContext.cancellationToken;
    parent?.addListener(token.cancel);
    _runTokens.add(token);
    try {
      final execution =
          AutomationInvocationService(
            engine: executionEngine,
            registry: () => registry,
            queues: queueManager,
          ).invokeOrThrow(
            GraphInvocation(
              target: InvocationDocument(parsed),
              origin: InvocationOrigin.streamPlan,
              sourceId: planId,
              sourceSubId: sourceSubId,
              dispatch: InvocationDispatch.documentQueue,
              context: InvocationContext.capture(executionContext),
              cancellation: token,
              onNodeEnter: onNodeEnter,
              onNodeExit: onNodeExit,
            ),
          );
      return await execution;
    } finally {
      _runTokens.remove(token);
      parent?.removeListener(token.cancel);
    }
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
    if (_closing != null) throw StateError('Stream Plan runtime is closed.');
    final previous = _transition;
    // Reserve our position before awaiting the preceding transition. Otherwise
    // multiple rapid commands wait for the same predecessor and run together.
    final release = Completer<void>();
    _transition = release.future;
    try {
      if (previous != null) await previous;
      if (_closing != null) throw StateError('Stream Plan runtime is closed.');
      lastTransitionError = null;
      return await operation();
    } catch (error) {
      lastTransitionError = error;
      notifyListeners();
      rethrow;
    } finally {
      release.complete();
      if (identical(_transition, release.future)) _transition = null;
    }
  }
}

DartPluginManifest createStreamPlansPlugin({
  DartStreamPlanRuntime? runtime,
  DartPluginRegistry? registry,
  DartAutomationQueueManager? queueManager,
  GraphExecutionEngine? executionEngine,
}) {
  final activeRuntime = runtime ?? DartStreamPlanRuntime();
  if (executionEngine != null) activeRuntime.executionEngine = executionEngine;
  if (queueManager != null) activeRuntime.queueManager = queueManager;
  return DartPluginManifest(
    id: PluginId('stream-plans'),
    name: 'Stream Plans',
    resources: streamPlansResourceContracts,
    actions: [
      ActionSpec<StreamPlanNavigationConfig, RuntimeMap>(
        pluginId: PluginId('stream-plans'),
        actionId: ActionId('nextSegment'),
        displayName: 'Next Segment',
        configSchema: _segmentSchema,
        configCodec: streamPlanNavigationConfigCodec,
        invoke: (config, context) => _nextSegment(
          config,
          context,
          runtime: activeRuntime,
          registry: registry,
        ),
      ),
      ActionSpec<StreamPlanNavigationConfig, RuntimeMap>(
        pluginId: PluginId('stream-plans'),
        actionId: ActionId('prevSegment'),
        displayName: 'Previous Segment',
        configSchema: _segmentSchema,
        configCodec: streamPlanNavigationConfigCodec,
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

Future<RuntimeMap> _nextSegment(
  StreamPlanNavigationConfig config,
  EvaluationContext context, {
  required DartStreamPlanRuntime runtime,
  DartPluginRegistry? registry,
}) async {
  final planId = config.planId ?? runtime.activePlanId;
  final segments = config.segments;
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

Future<RuntimeMap> _previousSegment(
  StreamPlanNavigationConfig config,
  EvaluationContext context, {
  required DartStreamPlanRuntime runtime,
  DartPluginRegistry? registry,
}) async {
  final planId = config.planId ?? runtime.activePlanId;
  final segments = config.segments;
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
  StreamPlanNavigationConfig config, {
  required bool forward,
}) {
  final segments = config.segments;
  if (segments == null) return config.segmentId;
  final plan = StreamPlanData.fromConfig({'segments': segments});
  return forward ? runtime.next(plan) : runtime.previous(plan);
}
