import 'dart:async';

import '../plugins/registry/plugin_registry.dart';
import '../schema/automation.dart';
import '../schema/profile.dart';
import 'expression.dart';
import 'graph_runtime.dart';
import 'automation_queue_manager.dart';

final class DartProfileRuntime {
  DartProfileRuntime({
    required this.registry,
    DartGraphRuntime? graphRuntime,
    this.queueManager,
  }) : graphRuntime = graphRuntime ?? const DartGraphRuntime();

  final DartPluginRegistry registry;
  final DartGraphRuntime graphRuntime;
  final DartAutomationQueueManager? queueManager;
  final Map<String, bool> _activeProfiles = {};
  final Map<String, DartProfileSession> _managedSessions = {};

  bool isActive(String profileId) => _activeProfiles[profileId] ?? false;

  bool hasManagedSession(String profileId) =>
      _managedSessions.containsKey(profileId);

  bool shouldBeActive(ShowRunnerProfile profile, {EvaluationContext? context}) {
    final runtimeContext = context ?? EvaluationContext();
    return switch (profile.activationMode) {
      'always' || 'automation' => true,
      'manual' => false,
      _ => evaluateBooleanCondition(
        profile.activationCondition,
        runtimeContext,
      ),
    };
  }

  Future<GraphExecutionResult?> reconcile(
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

  Future<GraphExecutionResult> activate(
    String profileId,
    ShowRunnerProfile profile, {
    EvaluationContext? context,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
  }) async {
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
    _activeProfiles[profileId] = true;
    return result;
  }

  Future<GraphExecutionResult> deactivate(
    String profileId,
    ShowRunnerProfile profile, {
    EvaluationContext? context,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
  }) async {
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
    _activeProfiles[profileId] = false;
    return result;
  }

  /// Changes a profile from a runtime action and owns the trigger subscription
  /// created by that action. The profile editor keeps using [activate] and
  /// [watch] separately so its existing close lifecycle remains explicit.
  Future<GraphExecutionResult?> setManagedActive(
    String profileId,
    ShowRunnerProfile profile, {
    required bool active,
    EvaluationContext? context,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
  }) async {
    if (active == isActive(profileId)) return null;
    if (!active) {
      await _managedSessions.remove(profileId)?.dispose();
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
    await _managedSessions.remove(profileId)?.dispose();
    _managedSessions[profileId] = watch(
      profileId,
      profile,
      context: context,
      onNodeEnter: onNodeEnter,
      onNodeExit: onNodeExit,
    );
  }

  Future<void> disposeManagedSession(String profileId) async {
    await _managedSessions.remove(profileId)?.dispose();
  }

  void forgetProfile(String profileId) {
    _activeProfiles.remove(profileId);
  }

  Future<void> dispose() async {
    final sessions = _managedSessions.values.toList();
    _managedSessions.clear();
    await Future.wait(sessions.map((session) => session.dispose()));
  }

  Future<GraphExecutionResult?> handleTrigger(
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
    if (!isActive(profileId)) return null;
    for (final target in _triggerTargets(profile)) {
      if (triggerEntry != null && !identical(target.entry, triggerEntry)) {
        continue;
      }
      if (target.pluginId != pluginId || target.triggerId != triggerId) {
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
    final subscriptions = <StreamSubscription<RuntimeMap>>[];
    final listenerRemovers = <void Function()>[];
    for (final target in _triggerTargets(profile)) {
      final pluginId = target.pluginId;
      final triggerId = target.triggerId;
      if (pluginId is! String || triggerId is! String) continue;
      if (pluginId == 'ShowRunner' && triggerId == 'autoRun') {
        void listener() {
          if (!isActive(profileId)) return;
          unawaited(
            handleTrigger(
              profileId,
              profile,
              pluginId,
              triggerId,
              {'triggerId': target.entry['id'], 'profileId': profileId},
              context: context,
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
      if (pluginId == 'ShowRunner' && triggerId == 'condition') {
        final condition = target.config['condition'];
        var lastValue = target.config['runImmediately'] == true ? false : null;
        bool evaluate() => evaluateBooleanCondition(
          condition is Map
              ? Map<String, dynamic>.from(condition)
              : const <String, dynamic>{},
          _withRegistryState(context),
        );
        final initialValue = evaluate();
        lastValue ??= initialValue;
        if (lastValue == false && initialValue) {
          unawaited(
            handleTrigger(
              profileId,
              profile,
              pluginId,
              triggerId,
              {'triggerId': target.entry['id'], 'profileId': profileId},
              context: context,
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
            unawaited(
              handleTrigger(
                profileId,
                profile,
                pluginId,
                triggerId,
                {'triggerId': target.entry['id'], 'profileId': profileId},
                context: context,
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
      final definition = registry.findTrigger(pluginId, triggerId);
      if (definition == null || !registry.isPluginEnabled(pluginId)) continue;
      subscriptions.add(
        (definition.listenForConfig?.call(target.config) ?? definition.listen())
            .listen((payload) {
              if (definition.matches?.call(target.config, payload) == false) {
                return;
              }
              unawaited(
                _runTriggerTarget(
                  profileId,
                  target,
                  payload,
                  context: context,
                  onNodeEnter: onNodeEnter,
                  onNodeExit: onNodeExit,
                ),
              );
            }),
      );
    }
    return DartProfileSession._(subscriptions, listenerRemovers);
  }

  Iterable<
    ({String? pluginId, String? triggerId, JsonMap config, JsonMap entry})
  >
  _triggerTargets(ShowRunnerProfile profile) sync* {
    for (final trigger in profile.triggers) {
      final rawAutomation = trigger['automation'];
      if (rawAutomation is! Map) continue;
      final automation = AutomationData.fromJson(
        Map<String, dynamic>.from(rawAutomation),
      );
      if (automation.triggerNodes.isNotEmpty) {
        for (final node in automation.triggerNodes) {
          final pluginId = node['plugin'] as String?;
          final triggerId = node['trigger'] as String?;
          final nodeId = node['id']?.toString();
          if (pluginId == null ||
              triggerId == null ||
              nodeId == null ||
              nodeId.isEmpty) {
            continue;
          }
          yield (
            pluginId: pluginId,
            triggerId: triggerId,
            config: _triggerConfig(node['config']),
            entry: {
              ...trigger,
              'id': nodeId,
              'plugin': pluginId,
              'trigger': triggerId,
              'config': _triggerConfig(node['config']),
              'stop': node['stop'] ?? trigger['stop'],
            },
          );
        }
        continue;
      }
      final pluginId = trigger['plugin'] as String?;
      final triggerId = trigger['trigger'] as String?;
      if (pluginId != null && triggerId != null) {
        yield (
          pluginId: pluginId,
          triggerId: triggerId,
          config: _triggerConfig(trigger['config']),
          entry: trigger,
        );
      }
    }
  }

  JsonMap _triggerConfig(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  EvaluationContext _withRegistryState(EvaluationContext? context) =>
      EvaluationContext(
        locals: Map<String, dynamic>.from(context?.locals ?? const {}),
        contextState: {...registry.stateContext(), ...?context?.contextState},
      );

  Future<GraphExecutionResult> _runTriggerTarget(
    String profileId,
    ({String? pluginId, String? triggerId, JsonMap config, JsonMap entry})
    target,
    RuntimeMap payload, {
    EvaluationContext? context,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
  }) {
    final rawAutomation = target.entry['automation'];
    if (rawAutomation is! Map) {
      throw const FormatException(
        'Profile trigger must contain a V2 automation document.',
      );
    }
    final automation = AutomationData.fromJson(
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
        },
      ),
      onNodeEnter: onNodeEnter,
      onNodeExit: onNodeExit,
      queueId: target.entry['queue']?.toString(),
      sourceMetadata: {
        'sourceType': 'profile',
        'sourceId': profileId,
        if (sourceSubId != null && sourceSubId.isNotEmpty)
          'sourceSubId': sourceSubId,
      },
    );
  }

  Future<GraphExecutionResult> _runAutomation(
    AutomationData automation,
    EvaluationContext context, {
    String? queueId,
    RuntimeMap? sourceMetadata,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
  }) async {
    final queue = queueManager;
    final effectiveQueueId = queueId ?? automation.queueId;
    if (queue != null && effectiveQueueId != null) {
      final item = await queue.enqueue(
        automation,
        context,
        queueId: effectiveQueueId,
        sourceMetadata: sourceMetadata,
      );
      return GraphExecutionResult(
        completed: true,
        steps: 0,
        nodeResults: const <String, RuntimeMap>{},
        contextState: Map<String, dynamic>.from(context.contextState),
        outputValues: {
          'queued': true,
          'queueId': effectiveQueueId,
          'itemId': item.id,
        },
      );
    }
    return graphRuntime.executeWithRegistry(
      graph: automation.graph,
      context: context,
      registry: registry,
      dataWires: automation.dataWires,
      subgraphs: automation.subgraphs,
      onNodeEnter: onNodeEnter,
      onNodeExit: onNodeExit,
    );
  }
}

final class DartProfileSession {
  DartProfileSession._(this._subscriptions, this._listenerRemovers);

  final List<StreamSubscription<RuntimeMap>> _subscriptions;
  final List<void Function()> _listenerRemovers;

  Future<void> dispose() async {
    await Future.wait(
      _subscriptions.map((subscription) => subscription.cancel()),
    );
    _subscriptions.clear();
    for (final remove in _listenerRemovers) {
      remove();
    }
    _listenerRemovers.clear();
  }
}

bool evaluateBooleanCondition(JsonMap condition, EvaluationContext context) {
  if (condition.isEmpty) return false;
  final type = condition['type'];
  if (type == 'group') {
    final operands = condition['operands'] is List
        ? (condition['operands'] as List).whereType<Map>()
        : const <Map>[];
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
