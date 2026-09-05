import '../schema/automation.dart';
import '../plugins/registry/plugin_registry.dart';
import 'expression.dart';

typedef GraphAction =
    Future<Object?> Function(
      GraphNode node,
      RuntimeMap config,
      EvaluationContext context,
    );

final class GraphExecutionResult {
  const GraphExecutionResult({
    required this.completed,
    required this.steps,
    required this.nodeResults,
    required this.contextState,
    this.outputValues = const <String, dynamic>{},
  });

  final bool completed;
  final int steps;
  final Map<String, RuntimeMap> nodeResults;
  final Map<String, dynamic> contextState;
  final Map<String, dynamic> outputValues;
}

RuntimeMap? _normalizeActionResult(Object? result) {
  if (result is Map) {
    return {
      for (final entry in result.entries) entry.key.toString(): entry.value,
    };
  }
  return result == null ? null : {'_result': result};
}

final class DartGraphRuntime {
  const DartGraphRuntime({this.maxSteps = 10000, this.maxDepth = 64});

  final int maxSteps;
  final int maxDepth;

  Future<GraphExecutionResult> executeWithRegistry({
    required AutomationGraph graph,
    required EvaluationContext context,
    required DartPluginRegistry registry,
    List<DataWire> dataWires = const <DataWire>[],
    List<SubgraphDefinition> subgraphs = const <SubgraphDefinition>[],
    String? entryNodeId,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
  }) {
    return execute(
      graph: graph,
      context: context,
      dataWires: dataWires,
      subgraphs: {for (final subgraph in subgraphs) subgraph.id: subgraph},
      entryNodeId: entryNodeId,
      onNodeEnter: onNodeEnter,
      onNodeExit: onNodeExit,
      action: (node, config, runtimeContext) =>
          registry.invoke(node, runtimeContext, config),
    );
  }

  Future<GraphExecutionResult> execute({
    required AutomationGraph graph,
    required EvaluationContext context,
    required GraphAction action,
    List<DataWire> dataWires = const <DataWire>[],
    Map<String, SubgraphDefinition> subgraphs =
        const <String, SubgraphDefinition>{},
    List<JsonMap>? outputDefinitions,
    String? entryNodeId,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
    int depth = 0,
  }) async {
    if (depth > maxDepth) {
      throw StateError('Maximum graph recursion depth exceeded: $maxDepth');
    }
    final nodes = {for (final node in graph.nodes) node.id: node};
    final outgoing = <String, List<GraphEdge>>{};
    for (final edge in graph.edges) {
      outgoing.putIfAbsent(edge.from, () => []).add(edge);
    }
    final results = <String, RuntimeMap>{};
    final loopState = <String, dynamic>{};
    final runtimeContext = EvaluationContext(
      locals: Map<String, dynamic>.from(context.locals),
      contextState: Map<String, dynamic>.from(context.contextState),
      nodeResults: results,
    );
    var current = entryNodeId ?? graph.entryNodeId;
    var steps = 0;
    var didReturn = false;
    var outputValues = <String, dynamic>{};

    if (current == 'trigger' && !nodes.containsKey(current)) {
      current = outgoing[current]?.firstOrNull?.to ?? '';
    }
    while (current.isNotEmpty && steps < maxSteps) {
      final node = nodes[current];
      if (node == null) break;
      steps++;
      onNodeEnter?.call(node.id);
      final edges = outgoing[node.id] ?? const <GraphEdge>[];
      switch (node.type) {
        case 'action':
        case 'queue.addItem':
        case 'overlay.pushChat':
          final executionNode = _compatibilityActionNode(node);
          final result = await action(
            executionNode,
            _compatibilityConfig(
              node,
              _config(node, dataWires, runtimeContext),
            ),
            runtimeContext,
          );
          final normalizedResult = _normalizeActionResult(result);
          if (normalizedResult != null) results[node.id] = normalizedResult;
          final resultMapping = node.data['resultMapping'];
          if (resultMapping is Map) {
            for (final entry in resultMapping.entries) {
              runtimeContext.contextState[entry.value.toString()] = _getPath(
                normalizedResult,
                entry.key.toString(),
              );
            }
          }
          current =
              _next(edges, 'completed')?.to ??
              _next(edges, 'out')?.to ??
              edges.firstOrNull?.to ??
              '';
        case 'if':
          final condition = _truthy(
            evaluateExpression(node.data['condition'], runtimeContext),
          );
          current = _next(edges, condition ? 'then' : 'else')?.to ?? '';
        case 'while':
          final iterations = (loopState[node.id] as int?) ?? 0;
          final condition = _truthy(
            evaluateExpression(node.data['condition'], runtimeContext),
          );
          final limit =
              (node.data['maxIterations'] as num?)?.toInt() ?? maxSteps;
          if (!condition || iterations >= limit) {
            loopState.remove(node.id);
            current = _next(edges, 'next')?.to ?? '';
          } else {
            loopState[node.id] = iterations + 1;
            current = _next(edges, 'body')?.to ?? '';
          }
        case 'for':
          final state = loopState[node.id] as RuntimeMap?;
          final loop =
              state ??
              <String, dynamic>{
                'current': _number(
                  evaluateExpression(node.data['start'], runtimeContext),
                ),
                'end': _number(
                  evaluateExpression(node.data['end'], runtimeContext),
                ),
                'step': _number(
                  evaluateExpression(node.data['step'], runtimeContext),
                ),
              };
          if (state == null) loopState[node.id] = loop;
          if (loop['step'] == 0 || loop['current'] >= loop['end']) {
            loopState.remove(node.id);
            current = _next(edges, 'next')?.to ?? '';
          } else {
            runtimeContext.locals[node.data['variable'] as String? ?? 'index'] =
                loop['current'];
            loop['current'] = loop['current'] + loop['step'];
            current = _next(edges, 'body')?.to ?? '';
          }
        case 'forEach':
          final state = loopState[node.id] as RuntimeMap?;
          final collection =
              state?['collection'] ??
              evaluateExpression(node.data['collection'], runtimeContext);
          final index = (state?['index'] as int?) ?? 0;
          if (state == null) {
            loopState[node.id] = {'collection': collection, 'index': 0};
          }
          if (collection is! List || index >= collection.length) {
            loopState.remove(node.id);
            current = _next(edges, 'next')?.to ?? '';
          } else {
            runtimeContext.locals[node.data['variable'] as String? ?? 'item'] =
                collection[index];
            final indexVariable = node.data['indexVariable'] as String?;
            if (indexVariable != null) {
              runtimeContext.locals[indexVariable] = index;
            }
            loopState[node.id] = {'collection': collection, 'index': index + 1};
            current = _next(edges, 'body')?.to ?? '';
          }
        case 'switch':
          final value = evaluateExpression(
            node.data['expression'],
            runtimeContext,
          );
          final matching =
              (node.data['cases'] is List
                      ? node.data['cases'] as List
                      : const [])
                  .whereType<Map>()
                  .firstWhere(
                    (item) => item['value'] == value,
                    orElse: () => const {},
                  );
          final port = matching.isNotEmpty
              ? matching['port'] as String?
              : 'default';
          current = _next(edges, port ?? 'default')?.to ?? '';
        case 'return':
          outputValues = _returnValues(node.data['outputs'], runtimeContext);
          didReturn = true;
          current = '';
        case 'subgraphCall' || 'subgraph' || 'call':
          final subgraphId = node.data['subgraphId']?.toString();
          final subgraph = subgraphId == null ? null : subgraphs[subgraphId];
          if (subgraph == null) {
            throw StateError('Unknown subgraph: $subgraphId');
          }
          final inputs = _subgraphInputs(
            node,
            subgraph,
            dataWires,
            runtimeContext,
          );
          final nested = await execute(
            graph: AutomationGraph(
              nodes: subgraph.nodes,
              edges: subgraph.edges,
              entryNodeId: subgraph.entryNodeId,
            ),
            action: action,
            dataWires: subgraph.dataWires,
            subgraphs: subgraphs,
            entryNodeId: subgraph.entryNodeId,
            outputDefinitions: subgraph.outputs,
            context: EvaluationContext(
              locals: inputs,
              contextState: runtimeContext.contextState,
            ),
            onNodeEnter: onNodeEnter,
            onNodeExit: onNodeExit,
            depth: depth + 1,
          );
          results.addAll(nested.nodeResults);
          results[node.id] = Map<String, dynamic>.from(nested.outputValues);
          runtimeContext.contextState.addAll(nested.contextState);
          current =
              _next(edges, 'completed')?.to ??
              _next(edges, 'out')?.to ??
              edges.firstOrNull?.to ??
              '';
        default:
          current = edges.firstOrNull?.to ?? '';
      }
      onNodeExit?.call(node.id);
    }
    return GraphExecutionResult(
      completed: current.isEmpty,
      steps: steps,
      nodeResults: results,
      contextState: runtimeContext.contextState,
      outputValues: didReturn
          ? {
              ...outputValues,
              ..._boundaryOutputValues(dataWires, runtimeContext),
            }
          : {
              ..._definitionOutputValues(outputDefinitions, runtimeContext),
              ..._boundaryOutputValues(dataWires, runtimeContext),
            },
    );
  }
}

GraphEdge? _next(List<GraphEdge> edges, String port) =>
    edges.where((edge) => edge.port == port).firstOrNull;

RuntimeMap _config(
  GraphNode node,
  List<DataWire> dataWires,
  EvaluationContext context,
) {
  final config = node.data['config'];
  final resolved = config is Map ? _cloneMap(config) : <String, dynamic>{};
  for (final wire in dataWires.where((wire) => wire.toNode == node.id)) {
    final source = _resolveWireSource(wire.fromNode, wire.fromPort, context);
    _setPath(resolved, wire.toPort, source);
  }
  final interpolated = interpolateRuntimeValue(resolved, context);
  return interpolated is Map
      ? Map<String, dynamic>.from(interpolated)
      : resolved;
}

GraphNode _compatibilityActionNode(GraphNode node) {
  if (node.type == 'action') return node;
  final compatibility = switch (node.type) {
    'queue.addItem' => const {'plugin': 'ShowRunner', 'action': 'addToQueue'},
    'overlay.pushChat' => const {
      'plugin': 'overlays',
      'action': 'pushChatMessage',
    },
    _ => const <String, dynamic>{},
  };
  return GraphNode(
    id: node.id,
    type: 'action',
    x: node.x,
    y: node.y,
    data: {...node.data, ...compatibility},
  );
}

RuntimeMap _compatibilityConfig(GraphNode node, RuntimeMap config) {
  switch (node.type) {
    case 'queue.addItem':
      return {
        ...config,
        'queue': config['queue'] ?? node.data['queueName'] ?? 'default',
        if (config['automation'] == null && node.data['automation'] != null)
          'automation': node.data['automation'],
        if (config['payload'] == null && node.data['payload'] != null)
          'payload': node.data['payload'],
      };
    case 'overlay.pushChat':
      return {
        ...config,
        if (config['targetWidget'] == null && node.data['targetWidget'] != null)
          'targetWidget': node.data['targetWidget'],
        'message': config['message'] ?? node.data['message'] ?? '',
      };
    default:
      return config;
  }
}

RuntimeMap _subgraphInputs(
  GraphNode node,
  SubgraphDefinition subgraph,
  List<DataWire> dataWires,
  EvaluationContext context,
) {
  final rawInputs = node.data['inputs'];
  final inputs = <String, dynamic>{};
  for (final parameter in subgraph.parameters) {
    final name = parameter['name']?.toString();
    if (name == null || name.isEmpty) continue;
    final wired = dataWires
        .where((wire) => wire.toNode == node.id && wire.toPort == name)
        .firstOrNull;
    if (wired != null) {
      inputs[name] = _resolveWireSource(
        wired.fromNode,
        wired.fromPort,
        context,
      );
      continue;
    }
    if (rawInputs is Map && rawInputs.containsKey(name)) {
      inputs[name] = _evaluateInput(rawInputs[name], context);
      continue;
    }
    inputs[name] = parameter['default'];
  }
  return inputs;
}

dynamic _evaluateInput(dynamic input, EvaluationContext context) {
  if (input is Map && input['type'] is String) {
    return evaluateExpression(input, context);
  }
  return input;
}

dynamic _resolveWireSource(
  String fromNode,
  String fromPort,
  EvaluationContext context,
) {
  if (fromNode == 'trigger') {
    return _getPath(context.contextState, fromPort);
  }
  if (fromNode.startsWith('__param:')) {
    final value = context.locals[fromNode.substring('__param:'.length)];
    return fromPort == 'value' ? value : _getPath(value, fromPort);
  }
  if (fromNode.startsWith('__output:')) {
    return context.nodeResults[fromNode]?[fromPort];
  }
  return _getPath(context.nodeResults[fromNode], fromPort);
}

Map<String, dynamic> _returnValues(
  dynamic outputs,
  EvaluationContext context,
) => outputs is Map
    ? {
        for (final entry in outputs.entries)
          entry.key.toString(): _evaluateInput(entry.value, context),
      }
    : <String, dynamic>{};

Map<String, dynamic> _definitionOutputValues(
  List<JsonMap>? definitions,
  EvaluationContext context,
) => definitions == null
    ? <String, dynamic>{}
    : {
        for (final definition in definitions)
          if (definition['name'] is String && definition['expression'] != null)
            definition['name'].toString(): _evaluateInput(
              definition['expression'],
              context,
            ),
      };

Map<String, dynamic> _boundaryOutputValues(
  List<DataWire> dataWires,
  EvaluationContext context,
) => {
  for (final wire in dataWires.where(
    (wire) => wire.toNode.startsWith('__output:'),
  ))
    wire.toNode.substring('__output:'.length): _resolveWireSource(
      wire.fromNode,
      wire.fromPort,
      context,
    ),
};

bool _truthy(dynamic value) => value is bool
    ? value
    : value != null && value != 0 && value != '' && value != false;
num _number(dynamic value) =>
    value is num ? value : num.tryParse('$value') ?? 0;

RuntimeMap _cloneMap(Map value) => {
  for (final entry in value.entries)
    entry.key.toString(): entry.value is Map
        ? _cloneMap(entry.value as Map)
        : entry.value is List
        ? (entry.value as List)
              .map((item) => item is Map ? _cloneMap(item) : item)
              .toList()
        : entry.value,
};

void _setPath(RuntimeMap target, String path, dynamic value) {
  final parts = path.split('.').where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) return;
  var current = target;
  for (final part in parts.take(parts.length - 1)) {
    final next = current[part];
    if (next is Map) {
      current = Map<String, dynamic>.from(next);
      target[part] = current;
    } else {
      current[part] = <String, dynamic>{};
      current = current[part] as RuntimeMap;
    }
  }
  current[parts.last] = value;
}

dynamic _getPath(dynamic source, String path) {
  if (source == null) return null;
  var current = source;
  for (final part in path.split('.').where((part) => part.isNotEmpty)) {
    if (current is Map) {
      current = current[part];
    } else if (current is List) {
      final index = int.tryParse(part);
      if (index == null || index < 0 || index >= current.length) return null;
      current = current[index];
    } else {
      return null;
    }
  }
  return current;
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
