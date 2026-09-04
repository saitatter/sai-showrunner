import 'dart:async';

import '../plugins/registry/plugin_registry.dart';
import '../schema/automation.dart';
import '../schema/profile.dart';
import 'expression.dart';
import 'graph_runtime.dart';

final class DartProfileRuntime {
  DartProfileRuntime({required this.registry, DartGraphRuntime? graphRuntime})
    : graphRuntime = graphRuntime ?? const DartGraphRuntime();

  final DartPluginRegistry registry;
  final DartGraphRuntime graphRuntime;
  final Map<String, bool> _activeProfiles = {};

  bool isActive(String profileId) => _activeProfiles[profileId] ?? false;

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
      context ?? EvaluationContext(),
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
      context ?? EvaluationContext(),
      onNodeEnter: onNodeEnter,
      onNodeExit: onNodeExit,
    );
    _activeProfiles[profileId] = false;
    return result;
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
    for (final trigger in profile.triggers) {
      if (triggerEntry != null && !identical(trigger, triggerEntry)) continue;
      final matchesTopLevel =
          trigger['plugin'] == pluginId && trigger['trigger'] == triggerId;
      final triggerNodes = trigger['triggerNodes'];
      final matchesNode =
          triggerNodes is List &&
          triggerNodes.whereType<Map>().any(
            (node) =>
                node['plugin'] == pluginId && node['trigger'] == triggerId,
          );
      if (!matchesTopLevel && !matchesNode) continue;
      return _runAutomation(
        AutomationData.fromJson(trigger),
        EvaluationContext(
          locals: Map<String, dynamic>.from(context?.locals ?? const {}),
          contextState: {
            ...?context?.contextState,
            ...payload,
            'event': payload,
          },
        ),
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
    for (final target in _triggerTargets(profile)) {
      final pluginId = target.pluginId;
      final triggerId = target.triggerId;
      if (pluginId is! String || triggerId is! String) continue;
      final definition = registry.findTrigger(pluginId, triggerId);
      if (definition == null || !registry.isPluginEnabled(pluginId)) continue;
      subscriptions.add(
        definition.listen().listen(
          (payload) {
            if (definition.matches?.call(target.config, payload) == false) {
              return;
            }
            unawaited(
              handleTrigger(
                profileId,
                profile,
                pluginId,
                triggerId,
                payload,
                context: context,
                onNodeEnter: onNodeEnter,
                onNodeExit: onNodeExit,
                triggerEntry: target.entry,
              ),
            );
          },
        ),
      );
    }
    return DartProfileSession._(subscriptions);
  }

  Iterable<({
    String? pluginId,
    String? triggerId,
    JsonMap config,
    JsonMap entry,
  })> _triggerTargets(
    ShowRunnerProfile profile,
  ) sync* {
    for (final trigger in profile.triggers) {
      final seen = <String>{};
      final pluginId = trigger['plugin'] as String?;
      final triggerId = trigger['trigger'] as String?;
      if (pluginId != null &&
          triggerId != null &&
          seen.add('$pluginId\u0000$triggerId')) {
        yield (
          pluginId: pluginId,
          triggerId: triggerId,
          config: _triggerConfig(trigger['config']),
          entry: trigger,
        );
      }
      final triggerNodes = trigger['triggerNodes'];
      if (triggerNodes is List) {
        for (final node in triggerNodes.whereType<Map>()) {
          final nodePluginId = node['plugin'] as String?;
          final nodeTriggerId = node['trigger'] as String?;
          if (nodePluginId != null &&
              nodeTriggerId != null &&
              seen.add('$nodePluginId\u0000$nodeTriggerId')) {
            yield (
              pluginId: nodePluginId,
              triggerId: nodeTriggerId,
              config: _triggerConfig(node['config']),
              entry: trigger,
            );
          }
        }
      }
    }
  }

  JsonMap _triggerConfig(dynamic value) => value is Map
      ? Map<String, dynamic>.from(value)
      : <String, dynamic>{};

  Future<GraphExecutionResult> _runAutomation(
    AutomationData automation,
    EvaluationContext context, {
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
  }) => graphRuntime.executeWithRegistry(
    graph: automation.graph,
    context: context,
    registry: registry,
    dataWires: automation.dataWires,
    subgraphs: automation.subgraphs,
    onNodeEnter: onNodeEnter,
    onNodeExit: onNodeExit,
  );
}

final class DartProfileSession {
  DartProfileSession._(this._subscriptions);

  final List<StreamSubscription<RuntimeMap>> _subscriptions;

  Future<void> dispose() async {
    await Future.wait(
      _subscriptions.map((subscription) => subscription.cancel()),
    );
    _subscriptions.clear();
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
