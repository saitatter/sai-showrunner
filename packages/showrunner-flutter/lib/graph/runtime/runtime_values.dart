import 'package:sai_nodes_core/sai_nodes_core.dart' show PortRef;
import '../../runtime/expression.dart';
import '../domain/automation_document.dart';
import 'automation_runtime_projection.dart';

Object? evaluateRuntimeInput(Object? value, EvaluationContext context) =>
    value is Map && value['type'] is String
    ? evaluateExpression(value, context)
    : value;

/// Derived runtime value lookup. It never mutates the authoring document.
final class RuntimeValueResolver {
  RuntimeValueResolver(this.projection) {
    final spaces = [
      projection.graph,
      ...projection.subgraphs.map((subgraph) => subgraph.body),
    ];
    nodes = {
      for (final space in spaces)
        for (final node in space.nodes) node.id: node,
    };
    bindings = {
      for (final space in spaces)
        for (final binding in space.dataWires)
          PortRef(nodeId: binding.toNode, portId: binding.toPort): binding,
    };
    variables = projection.variables;
    parameters = projection.parameterNodes;
    for (final binding in bindings.values) {
      (_byNode[binding.toNode] ??= []).add(binding);
    }
  }
  final AutomationRuntimeProjection projection;
  late final Map<String, RuntimeNode> nodes;
  late final Map<PortRef, RuntimeValueBinding> bindings;
  late final Map<String, RuntimeVariableBinding> variables;
  late final Map<String, String> parameters;
  final Map<String, List<RuntimeValueBinding>> _byNode = {};
  Iterable<RuntimeValueBinding> inputsFor(String nodeId) =>
      _byNode[nodeId] ?? const [];
  Object? resolve(
    String nodeId,
    String path,
    EvaluationContext context, [
    Set<String>? resolving,
  ]) {
    final visited = resolving ?? <String>{};
    if (!visited.add(nodeId)) {
      throw StateError('Cyclic variable value dependency at $nodeId.');
    }
    try {
      final variable = variables[nodeId];
      if (variable != null) {
        final binding = bindings[PortRef(nodeId: nodeId, portId: 'value')];
        final value = binding == null
            ? (context.locals.containsKey(variable.name)
                  ? context.locals[variable.name]
                  : variable.value)
            : resolve(binding.fromNode, binding.fromPort, context, visited);
        context.locals[variable.name] = value;
        context.nodeResults[nodeId] = {'value': value};
        return path.isEmpty || path == 'value' ? value : _path(value, path);
      }
      final parameter = parameters[nodeId];
      if (parameter != null) {
        final value = context.locals[parameter];
        return path.isEmpty || path == 'value' ? value : _path(value, path);
      }
      final node = nodes[nodeId];
      if (node?.type == 'trigger') {
        final event = context.contextState['trigger'];
        return _path(event is Map ? event : context.contextState, path);
      }
      if (node?.type == 'for' && path == 'loop:index') {
        return context.nodeResults[nodeId]?['index'] ??
            context.locals[node!.data['variable'] ?? 'index'];
      }
      if (node?.type == 'forEach') {
        if (path == 'loop:item') {
          return context.nodeResults[nodeId]?['item'] ??
              context.locals[node!.data['variable'] ?? 'item'];
        }
        if (path == 'loop:index') {
          return context.nodeResults[nodeId]?['index'] ??
              context.locals[node!.data['indexVariable'] ?? 'index'];
        }
      }
      if (node?.type == 'while' && path == 'loop:iteration') {
        return context.nodeResults[nodeId]?['iteration'];
      }
      return _path(context.nodeResults[nodeId], path);
    } finally {
      visited.remove(nodeId);
    }
  }

  Object? input(
    String nodeId,
    String key,
    Object? fallback,
    EvaluationContext context,
  ) {
    final binding = bindings[PortRef(nodeId: nodeId, portId: key)];
    return binding == null
        ? evaluateRuntimeInput(fallback, context)
        : resolve(binding.fromNode, binding.fromPort, context);
  }

  void seedScope(String spaceId, EvaluationContext context) {
    for (final entry in variables.values.where(
      (value) => value.spaceId == spaceId,
    )) {
      context.locals.putIfAbsent(entry.name, () => entry.value);
    }
  }

  Map<String, dynamic> outputs(
    String nodeId,
    Map expressions,
    EvaluationContext context,
  ) => {
    for (final entry in expressions.entries)
      entry.key.toString(): input(
        nodeId,
        entry.key.toString(),
        entry.value,
        context,
      ),
    for (final binding in inputsFor(nodeId))
      binding.toPort: resolve(binding.fromNode, binding.fromPort, context),
  };
  String spaceForSubgraph(String? id) =>
      id == null ? mainAutomationSpace : 'space:subgraph:$id';
}

Object? _path(Object? value, String path) {
  if (path.isEmpty) return value;
  for (final key in path.split('.')) {
    if (value is Map) {
      value = value[key];
    } else if (value is List) {
      final index = int.tryParse(key);
      if (index == null || index < 0 || index >= value.length) return null;
      value = value[index];
    } else {
      return null;
    }
  }
  return value;
}
