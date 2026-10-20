import 'cancellation.dart';
import 'profile_session.dart';
export 'profile_session.dart';
import 'automation_invocation_service.dart';
import 'graph_invocation.dart';
import '../graph/domain/automation_document.dart';
import '../graph/definitions/showrunner_graph_types.dart';
import 'dart:async';

import '../plugins/registry/plugin_registry.dart';
import '../schema/json.dart';
import '../schema/profile.dart';
import 'expression.dart';
import '../graph/runtime/graph_execution_engine.dart';
import 'automation_queue_manager.dart';

typedef _ProfileTriggerTarget = ({
  PluginId pluginId,
  TriggerId triggerId,
  JsonMap config,
  JsonMap entry,
});

final class DartProfileRuntime {
  DartProfileRuntime({
    required this.registry,
    GraphExecutionEngine? executionEngine,
    this.queueManager,
    this.onTriggerFailure,
  }) : executionEngine = executionEngine ?? CompiledExecutionEngine();

  final DartPluginRegistry registry;
  final GraphExecutionEngine executionEngine;
  final DartAutomationQueueManager? queueManager;
  final void Function(ProfileTriggerFailure)? onTriggerFailure;
  ProfileTriggerFailure? lastTriggerFailure;
  bool _closed = false;
  Future<void>? _closing;
  final Set<DartProfileSession> _sessions = {};
  final Set<DartCancellationToken> _runTokens = {};
  final Set<Future<InvocationResult>> _executions = {};
  void _reportTriggerFailure(String profileId, Object error, StackTrace stack) {
    if (_closed) return;
    final failure = ProfileTriggerFailure(profileId, error, stack);
    lastTriggerFailure = failure;
    try {
      onTriggerFailure?.call(failure);
    } catch (callbackError, callbackStack) {
      lastTriggerFailure = ProfileTriggerFailure(
        profileId,
        callbackError,
        callbackStack,
      );
    }
  }

  final Map<String, int> _sessionGenerations = {};
  final Map<String, Future<void>> _managedOperations = {};
  void _ensureOpen() {
    if (_closed) throw StateError('Profile runtime is closed.');
  }

  final Map<String, bool> _activeProfiles = {};
  final Map<String, DartProfileSession> _managedSessions = {};

  bool isActive(String profileId) => _activeProfiles[profileId] ?? false;

  bool hasManagedSession(String profileId) =>
      _managedSessions[profileId]?.isClosed == false;

  bool shouldBeActive(ShowRunnerProfile profile, {EvaluationContext? context}) {
    final runtimeContext = _withRegistryState(context);
    return switch (profile.activationMode) {
      'always' || 'automation' => true,
      'manual' => false,
      _ => evaluateBooleanCondition(
        profile.activationCondition,
        runtimeContext,
      ),
    };
  }

  Future<InvocationResult?> reconcile(
    String profileId,
    ShowRunnerProfile profile, {
    EvaluationContext? context,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
  }) async {
    final desired = shouldBeActive(profile, context: context);
    if (desired == isActive(profileId)) return null;
    return desired
        ? activate(
            profileId,
            profile,
            context: context,
            onNodeEnter: onNodeEnter,
            onNodeExit: onNodeExit,
          )
        : deactivate(
            profileId,
            profile,
            context: context,
            onNodeEnter: onNodeEnter,
            onNodeExit: onNodeExit,
          );
  }

  Future<InvocationResult> activate(
    String profileId,
    ShowRunnerProfile profile, {
    EvaluationContext? context,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
  }) async {
    _ensureOpen();
    final result = await _runAutomation(
      profile.activationAutomation,
      _withRegistryState(context),
      sourceMetadata: {
        'sourceType': 'profile',
        'sourceId': profileId,
        'sourceSubId': 'activation',
      },
      onNodeEnter: onNodeEnter,
      onNodeExit: onNodeExit,
    );
    _ensureOpen();
    _activeProfiles[profileId] = true;
    return result;
  }

  Future<InvocationResult> deactivate(
    String profileId,
    ShowRunnerProfile profile, {
    EvaluationContext? context,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
  }) async {
    _ensureOpen();
    final result = await _runAutomation(
      profile.deactivationAutomation,
      _withRegistryState(context),
      sourceMetadata: {
        'sourceType': 'profile',
        'sourceId': profileId,
        'sourceSubId': 'deactivation',
      },
      onNodeEnter: onNodeEnter,
      onNodeExit: onNodeExit,
    );
    _ensureOpen();
    _activeProfiles[profileId] = false;
    return result;
  }

  /// Changes a profile from a runtime action and owns the trigger subscription
  /// created by that action. The profile editor keeps using [activate] and
  /// [watch] separately so its existing close lifecycle remains explicit.
  Future<InvocationResult?> setManagedActive(
    String profileId,
    ShowRunnerProfile profile, {
    required bool active,
    EvaluationContext? context,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
  }) => _managedOperation(
    profileId,
    () => _setManagedActive(
      profileId,
      profile,
      active: active,
      context: context,
      onNodeEnter: onNodeEnter,
      onNodeExit: onNodeExit,
    ),
  );

  Future<T> _managedOperation<T>(
    String profileId,
    Future<T> Function() operation,
  ) {
    _ensureOpen();
    final previous = _managedOperations[profileId];
    final result = Completer<T>();
    Future<void> run() async {
      try {
        if (previous != null) await previous;
        _ensureOpen();
        result.complete(await operation());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    }

    final running = run();
    _managedOperations[profileId] = running;
    unawaited(
      running.then<void>((_) {
        if (identical(_managedOperations[profileId], running)) {
          _managedOperations.remove(profileId);
        }
      }),
    );
    return result.future;
  }

  Future<InvocationResult?> _setManagedActive(
    String profileId,
    ShowRunnerProfile profile, {
    required bool active,
    EvaluationContext? context,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
  }) async {
    if (active == isActive(profileId)) return null;
    if (!active) {
      await disposeManagedSession(profileId);
      return deactivate(
        profileId,
        profile,
        context: context,
        onNodeEnter: onNodeEnter,
        onNodeExit: onNodeExit,
      );
    }
    final result = await activate(
      profileId,
      profile,
      context: context,
      onNodeEnter: onNodeEnter,
      onNodeExit: onNodeExit,
    );
    await replaceManagedSession(
      profileId,
      profile,
      context: context,
      onNodeEnter: onNodeEnter,
      onNodeExit: onNodeExit,
    );
    return result;
  }

  Future<void> replaceManagedSession(
    String profileId,
    ShowRunnerProfile profile, {
    EvaluationContext? context,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
  }) async {
    _ensureOpen();
    final generation = (_sessionGenerations[profileId] ?? 0) + 1;
    _sessionGenerations[profileId] = generation;
    await _managedSessions.remove(profileId)?.dispose();
    if (_closed || generation != _sessionGenerations[profileId]) return;
    _managedSessions[profileId] = watch(
      profileId,
      profile,
      context: context,
      onNodeEnter: onNodeEnter,
      onNodeExit: onNodeExit,
    );
  }

  Future<void> disposeManagedSession(String profileId) async {
    _sessionGenerations[profileId] = (_sessionGenerations[profileId] ?? 0) + 1;
    await _managedSessions.remove(profileId)?.dispose();
  }

  void forgetProfile(String profileId) {
    _activeProfiles.remove(profileId);
  }

  Future<void> dispose() => _closing ??= _dispose();
  Future<void> _dispose() async {
    _closed = true;
    for (final token in _runTokens.toList()) {
      token.cancel();
    }
    final sessions = _sessions.toList();
    _managedSessions.clear();
    _activeProfiles.clear();
    try {
      await Future.wait(sessions.map((session) => session.dispose()));
    } finally {
      await Future.wait(
        _executions.toList().map(
          (execution) => execution.then<void>(
            (_) {},
            onError: (Object _, StackTrace _) {},
          ),
        ),
      );
      await Future.wait(_managedOperations.values.toList());
      _sessionGenerations.clear();
    }
  }

  Future<InvocationResult?> handleTrigger(
    String profileId,
    ShowRunnerProfile profile,
    String pluginId,
    String triggerId,
    RuntimeMap payload, {
    EvaluationContext? context,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
    JsonMap? triggerEntry,
  }) async {
    if (_closed || !isActive(profileId)) return null;
    final typedPluginId = PluginId(pluginId);
    final typedTriggerId = TriggerId(triggerId);
    for (final target in _triggerTargets(profile)) {
      if (triggerEntry != null &&
          (target.entry['id'] != triggerEntry['id'] ||
              target.entry['documentId'] != triggerEntry['documentId'])) {
        continue;
      }
      if (target.pluginId != typedPluginId ||
          target.triggerId != typedTriggerId) {
        continue;
      }
      return _runTriggerTarget(
        profileId,
        target,
        payload,
        context: context,
        onNodeEnter: onNodeEnter,
        onNodeExit: onNodeExit,
      );
    }
    return null;
  }

  DartProfileSession watch(
    String profileId,
    ShowRunnerProfile profile, {
    EvaluationContext? context,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
  }) {
    _ensureOpen();
    final subscriptions = <StreamSubscription<RuntimeMap>>[];
    final listenerRemovers = <void Function()>[];
    late final DartProfileSession session;
    session = DartProfileSession(
      subscriptions: subscriptions,
      listenerRemovers: listenerRemovers,
      onFailure: (error, stack) =>
          _reportTriggerFailure(profileId, error, stack),
      onDisposed: () => _sessions.remove(session),
    );
    _sessions.add(session);
    final parent = context?.cancellationToken;
    parent?.addListener(session.cancellation.cancel);
    if (parent != null) {
      listenerRemovers.add(
        () => parent.removeListener(session.cancellation.cancel),
      );
    }
    final sessionContext = EvaluationContext(
      locals: context?.locals,
      contextState: context?.contextState,
      cancellationToken: session.cancellation,
    );
    try {
      final sharedTargets = <String, List<_ProfileTriggerTarget>>{};
      for (final target in _triggerTargets(profile)) {
        final pluginId = target.pluginId;
        final triggerId = target.triggerId;
        if (pluginId == const PluginId('ShowRunner') &&
            triggerId == const TriggerId('autoRun')) {
          void listener() {
            if (!isActive(profileId)) return;
            session.dispatch(
              () => handleTrigger(
                profileId,
                profile,
                pluginId.value,
                triggerId.value,
                {'triggerId': target.entry['id'], 'profileId': profileId},
                context: sessionContext,
                onNodeEnter: onNodeEnter,
                onNodeExit: onNodeExit,
                triggerEntry: target.entry,
              ),
            );
          }

          registry.addListener(listener);
          listenerRemovers.add(() => registry.removeListener(listener));
          if (isActive(profileId)) listener();
          continue;
        }
        if (pluginId == const PluginId('ShowRunner') &&
            triggerId == const TriggerId('condition')) {
          final condition = target.config['condition'];
          var lastValue = target.config['runImmediately'] == true
              ? false
              : null;
          bool evaluate() => evaluateBooleanCondition(
            condition is Map
                ? Map<String, dynamic>.from(condition)
                : const <String, dynamic>{},
            _withRegistryState(context),
          );
          final initialValue = evaluate();
          lastValue ??= initialValue;
          if (lastValue == false && initialValue) {
            session.dispatch(
              () => handleTrigger(
                profileId,
                profile,
                pluginId.value,
                triggerId.value,
                {'triggerId': target.entry['id'], 'profileId': profileId},
                context: sessionContext,
                onNodeEnter: onNodeEnter,
                onNodeExit: onNodeExit,
                triggerEntry: target.entry,
              ),
            );
            lastValue = true;
          }
          void listener() {
            if (!isActive(profileId)) return;
            final currentValue = evaluate();
            if (currentValue && lastValue != true) {
              session.dispatch(
                () => handleTrigger(
                  profileId,
                  profile,
                  pluginId.value,
                  triggerId.value,
                  {'triggerId': target.entry['id'], 'profileId': profileId},
                  context: sessionContext,
                  onNodeEnter: onNodeEnter,
                  onNodeExit: onNodeExit,
                  triggerEntry: target.entry,
                ),
              );
            }
            lastValue = currentValue;
          }

          registry.addListener(listener);
          listenerRemovers.add(() => registry.removeListener(listener));
          continue;
        }
        final definition = registry.trigger(
          TriggerKey(plugin: pluginId, trigger: triggerId),
        );
        if (definition == null || !registry.isPluginEnabledId(pluginId)) {
          continue;
        }
        final configuredStream = definition.listenForRuntime(target.config);
        if (configuredStream != null) {
          subscriptions.add(
            configuredStream.cast<RuntimeMap>().listen((payload) {
              if (!definition.matchesRuntime(target.config, payload)) {
                return;
              }
              session.dispatch(
                () => _runTriggerTarget(
                  profileId,
                  target,
                  payload,
                  context: sessionContext,
                  onNodeEnter: onNodeEnter,
                  onNodeExit: onNodeExit,
                ),
              );
            }),
          );
        } else {
          sharedTargets
              .putIfAbsent(
                '${pluginId.value}\u0000${triggerId.value}',
                () => [],
              )
              .add(target);
        }
      }
      for (final targets in sharedTargets.values) {
        final first = targets.first;
        final pluginId = first.pluginId;
        final triggerId = first.triggerId;
        final definition = registry.trigger(
          TriggerKey(plugin: pluginId, trigger: triggerId),
        );
        if (definition == null) continue;
        subscriptions.add(
          definition.listenFromRuntime().cast<RuntimeMap>().listen((payload) {
            session.dispatch(
              () => _dispatchTriggerTargets(
                profileId,
                definition,
                targets,
                payload,
                context: sessionContext,
                onNodeEnter: onNodeEnter,
                onNodeExit: onNodeExit,
              ),
            );
          }),
        );
      }
      return session;
    } catch (error) {
      unawaited(
        session.dispose().catchError((Object cleanup, StackTrace stack) {
          _reportTriggerFailure(profileId, cleanup, stack);
        }),
      );
      rethrow;
    }
  }

  Iterable<_ProfileTriggerTarget> _triggerTargets(
    ShowRunnerProfile profile,
  ) sync* {
    for (final trigger in profile.triggers) {
      final automation = AutomationDocument.fromJson(
        Map<String, Object?>.from(trigger['automation'] as Map),
      );
      for (final node
          in automation.graph.spaces[mainAutomationSpace]!.nodes.values) {
        final contract = decodeContractNodeType(node.type, 'trigger');
        if (contract == null) continue;
        yield (
          pluginId: PluginId(contract.$1),
          triggerId: TriggerId(contract.$2),
          config: _triggerConfig(node.data['config']),
          entry: {
            ...trigger,
            'id': node.id,
            'documentId': automation.id,
            'plugin': contract.$1,
            'trigger': contract.$2,
            'config': _triggerConfig(node.data['config']),
            'stop': node.data['stop'] == true,
            'queue': automation.queueId,
          },
        );
      }
    }
  }

  JsonMap _triggerConfig(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  Future<void> _dispatchTriggerTargets(
    String profileId,
    DartTriggerContract definition,
    List<_ProfileTriggerTarget> targets,
    RuntimeMap payload, {
    EvaluationContext? context,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
  }) async {
    for (final target in targets) {
      if (_closed || !isActive(profileId)) return;
      context?.cancellationToken?.throwIfCancelled();
      if (!definition.matchesRuntime(target.config, payload)) {
        continue;
      }
      await _runTriggerTarget(
        profileId,
        target,
        payload,
        context: context,
        onNodeEnter: onNodeEnter,
        onNodeExit: onNodeExit,
      );
      if (target.entry['stop'] == true) break;
    }
  }

  EvaluationContext _withRegistryState(EvaluationContext? context) =>
      EvaluationContext(
        locals: Map<String, dynamic>.from(context?.locals ?? const {}),
        contextState: {...registry.stateContext(), ...?context?.contextState},
        cancellationToken: context?.cancellationToken,
      );

  Future<InvocationResult> _runTriggerTarget(
    String profileId,
    _ProfileTriggerTarget target,
    RuntimeMap payload, {
    EvaluationContext? context,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
  }) {
    final rawAutomation = target.entry['automation'];
    if (rawAutomation is! Map) {
      throw const FormatException(
        'Profile trigger must contain a version-1 automation document.',
      );
    }
    final automation = AutomationDocument.fromJson(
      Map<String, dynamic>.from(rawAutomation),
    );
    final sourceSubId = target.entry['id']?.toString();
    return _runAutomation(
      automation,
      EvaluationContext(
        locals: Map<String, dynamic>.from(context?.locals ?? const {}),
        contextState: {
          ...registry.stateContext(),
          ...?context?.contextState,
          ...payload,
          'event': payload,
          'trigger': payload,
        },
        cancellationToken: context?.cancellationToken,
      ),
      onNodeEnter: onNodeEnter,
      onNodeExit: onNodeExit,
      queueId: target.entry['queue']?.toString(),
      entryNodeId: target.entry['id']?.toString(),
      sourceMetadata: {
        'sourceType': 'profile',
        'sourceId': profileId,
        if (sourceSubId != null && sourceSubId.isNotEmpty)
          'sourceSubId': sourceSubId,
      },
    );
  }

  Future<InvocationResult> _runAutomation(
    AutomationDocument automation,
    EvaluationContext context, {
    String? queueId,
    String? entryNodeId,
    RuntimeMap? sourceMetadata,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
  }) async {
    _ensureOpen();
    final token = DartCancellationToken();
    final parent = context.cancellationToken;
    parent?.addListener(token.cancel);
    _runTokens.add(token);
    final execution =
        AutomationInvocationService(
          engine: executionEngine,
          registry: () => registry,
          queues: queueManager,
        ).invokeOrThrow(
          GraphInvocation(
            target: InvocationDocument(automation),
            origin: InvocationOrigin.profile,
            sourceId: sourceMetadata?['sourceId']?.toString() ?? automation.id,
            sourceSubId: sourceMetadata?['sourceSubId']?.toString(),
            dispatch: InvocationDispatch.documentQueue,
            queueId: queueId,
            entryNodeId: entryNodeId,
            context: InvocationContext.capture(context),
            cancellation: token,
            onNodeEnter: onNodeEnter,
            onNodeExit: onNodeExit,
          ),
        );
    _executions.add(execution);
    try {
      return await execution;
    } finally {
      _executions.remove(execution);
      _runTokens.remove(token);
      parent?.removeListener(token.cancel);
    }
  }
}

bool evaluateBooleanCondition(JsonMap condition, EvaluationContext context) {
  if (condition.isEmpty) return true;
  final type = condition['type'];
  if (type == 'group') {
    final operands = condition['operands'] is List
        ? (condition['operands'] as List).whereType<Map>()
        : const <Map>[];
    // Match the main application's BooleanExpression evaluator: an empty
    // group represents "No Conditions (Always On)" regardless of operator.
    if (operands.isEmpty) return true;
    final values = operands.map(
      (operand) =>
          evaluateBooleanCondition(Map<String, dynamic>.from(operand), context),
    );
    return condition['operator'] == 'and'
        ? values.every((value) => value)
        : values.any((value) => value);
  }
  if (type == 'value') {
    final left = _expressionValue(condition['lhs'], context);
    final right = _expressionValue(condition['rhs'], context);
    return switch (condition['operator']) {
      'lessThan' || '<' => _compare(left, right) < 0,
      'lessThanEq' || '<=' => _compare(left, right) <= 0,
      'equal' || '==' => left == right,
      'notEqual' || '!=' => left != right,
      'greaterThan' || '>' => _compare(left, right) > 0,
      'greaterThanEq' || '>=' => _compare(left, right) >= 0,
      _ => false,
    };
  }
  if (type == 'range') {
    final value = _expressionValue(condition['lhs'], context);
    final range = condition['range'];
    if (value is! num || range is! Map) return false;
    final minimum = (range['min'] as num?)?.toDouble();
    final maximum = (range['max'] as num?)?.toDouble();
    return (minimum == null || value >= minimum) &&
        (maximum == null || value <= maximum);
  }
  try {
    return _truthy(evaluateExpression(condition, context));
  } on ArgumentError {
    return false;
  }
}

dynamic _expressionValue(dynamic value, EvaluationContext context) {
  if (value is! Map) return value;
  switch (value['type']) {
    case 'value':
      return value['value'];
    case 'state':
      final plugin = value['plugin'];
      final state = value['state'];
      if (plugin is String && state is String) {
        final nested = context.contextState[plugin];
        if (nested is Map && nested.containsKey(state)) return nested[state];
        return context.contextState['$plugin.$state'];
      }
      return null;
    case 'resource':
      final resourceId = value['resourceId'];
      final state = value['state'];
      if (resourceId is String && state is String) {
        final nested = context.contextState[resourceId];
        return nested is Map ? nested[state] : null;
      }
      return null;
    default:
      return evaluateExpression(value, context);
  }
}

int _compare(dynamic left, dynamic right) {
  if (left is num && right is num) return left.compareTo(right);
  if (left is Comparable && right is Comparable) {
    try {
      return left.compareTo(right);
    } on Object {
      return 0;
    }
  }
  return 0;
}

bool _truthy(dynamic value) => value is bool
    ? value
    : value != null && value != 0 && value != '' && value != false;
