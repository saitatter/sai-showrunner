import '../schema/automation.dart';
import 'expression.dart';

enum GraphInstructionKind {
  action,
  branch,
  loop,
  returnNode,
  breakNode,
  continueNode,
  subgraph,
  passthrough,
}

final class GraphInstruction {
  const GraphInstruction({
    required this.index,
    required this.nodeId,
    required this.kind,
    required this.node,
    required this.outgoing,
    required this.targets,
  });

  final int index;
  final String nodeId;
  final GraphInstructionKind kind;
  final GraphNode node;
  final List<String> outgoing;
  final Map<String, int> targets;
}

final class CompiledGraph {
  const CompiledGraph({
    required this.instructions,
    required this.entryIndex,
    required this.nodeToInstruction,
    this.subgraphs = const <String, CompiledGraph>{},
    this.dataWires = const <DataWire>[],
    this.parameters = const <JsonMap>[],
    this.outputs = const <JsonMap>[],
  });

  final List<GraphInstruction> instructions;
  final int entryIndex;
  final Map<String, int> nodeToInstruction;
  final Map<String, CompiledGraph> subgraphs;
  final List<DataWire> dataWires;
  final List<JsonMap> parameters;
  final List<JsonMap> outputs;

  CompiledGraph withSubgraphs(Map<String, CompiledGraph> value) =>
      CompiledGraph(
        instructions: instructions,
        entryIndex: entryIndex,
        nodeToInstruction: nodeToInstruction,
        subgraphs: Map.unmodifiable(value),
        dataWires: dataWires,
        parameters: parameters,
        outputs: outputs,
      );

  GraphInstruction instructionForNode(String nodeId) {
    final index = nodeToInstruction[nodeId];
    if (index == null) throw StateError('Unknown compiled graph node: $nodeId');
    return instructions[index];
  }
}

RuntimeMap? _normalizeActionResult(Object? result) {
  if (result is Map) {
    return {
      for (final entry in result.entries) entry.key.toString(): entry.value,
    };
  }
  return result == null ? null : {'_result': result};
}

final class GraphCompileException implements Exception {
  const GraphCompileException(this.message);

  final String message;

  @override
  String toString() => 'GraphCompileException: $message';
}

final class DartGraphCompiler {
  const DartGraphCompiler();

  CompiledGraph compileAutomation(AutomationData automation) {
    final compiled = compile(automation.graph, dataWires: automation.dataWires);
    return compiled.withSubgraphs({
      for (final subgraph in automation.subgraphs)
        subgraph.id: compile(
          AutomationGraph(
            nodes: subgraph.nodes,
            edges: subgraph.edges,
            entryNodeId: subgraph.entryNodeId,
          ),
          dataWires: subgraph.dataWires,
          parameters: subgraph.parameters,
          outputs: subgraph.outputs,
        ),
    });
  }

  CompiledGraph compile(
    AutomationGraph graph, {
    String? entryNodeId,
    List<DataWire> dataWires = const <DataWire>[],
    List<JsonMap> parameters = const <JsonMap>[],
    List<JsonMap> outputs = const <JsonMap>[],
  }) {
    final nodes = {for (final node in graph.nodes) node.id: node};
    if (nodes.isEmpty) throw const GraphCompileException('Graph has no nodes.');
    final outgoing = <String, List<String>>{};
    for (final edge in graph.edges) {
      if (!nodes.containsKey(edge.from) || !nodes.containsKey(edge.to)) {
        throw GraphCompileException(
          'Edge ${edge.id} references an unknown node.',
        );
      }
      outgoing.putIfAbsent(edge.from, () => []).add(edge.to);
    }
    final entry = entryNodeId ?? graph.entryNodeId;
    if (!nodes.containsKey(entry)) {
      throw GraphCompileException('Entry node $entry does not exist.');
    }

    final ordered = <GraphNode>[];
    final visited = <String>{};
    void visit(String nodeId) {
      if (!visited.add(nodeId)) return;
      final node = nodes[nodeId]!;
      ordered.add(node);
      for (final next in outgoing[nodeId] ?? const <String>[]) {
        visit(next);
      }
    }

    visit(entry);
    final nodeToInstruction = <String, int>{
      for (var index = 0; index < ordered.length; index++)
        ordered[index].id: index,
    };
    final instructions = <GraphInstruction>[];
    for (final node in ordered) {
      final index = nodeToInstruction[node.id]!;
      instructions.add(
        GraphInstruction(
          index: index,
          nodeId: node.id,
          kind: _kind(node.type),
          node: node,
          outgoing: List.unmodifiable(outgoing[node.id] ?? const <String>[]),
          targets: Map.unmodifiable({
            for (final edge in graph.edges.where(
              (edge) => edge.from == node.id,
            ))
              edge.port ?? 'out': nodeToInstruction[edge.to] ?? -1,
          }),
        ),
      );
    }
    return CompiledGraph(
      instructions: List.unmodifiable(instructions),
      entryIndex: 0,
      nodeToInstruction: Map.unmodifiable(nodeToInstruction),
      dataWires: List.unmodifiable(dataWires),
      parameters: List.unmodifiable(parameters),
      outputs: List.unmodifiable(outputs),
    );
  }
}

typedef CompiledGraphAction =
    Future<Object?> Function(
      GraphInstruction instruction,
      RuntimeMap config,
      EvaluationContext context,
    );

typedef CompiledGraphStep =
    void Function(GraphInstruction instruction, int depth);

final class CompiledGraphExecutionResult {
  const CompiledGraphExecutionResult({
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

final class DartCompiledGraphRuntime {
  const DartCompiledGraphRuntime({this.maxSteps = 10000, this.maxDepth = 64});

  final int maxSteps;
  final int maxDepth;

  Future<CompiledGraphExecutionResult> execute({
    required CompiledGraph graph,
    required EvaluationContext context,
    required CompiledGraphAction action,
    CompiledGraphStep? onStep,
    int depth = 0,
    Map<String, CompiledGraph>? availableSubgraphs,
  }) async {
    if (depth > maxDepth) {
      throw StateError('Maximum graph recursion depth exceeded: $maxDepth');
    }
    final subgraphs = availableSubgraphs ?? graph.subgraphs;
    final results = <String, RuntimeMap>{};
    final runtimeContext = EvaluationContext(
      locals: Map<String, dynamic>.from(context.locals),
      contextState: Map<String, dynamic>.from(context.contextState),
      nodeResults: results,
    );
    var instructionIndex = graph.entryIndex;
    var steps = 0;
    final loopState = <String, RuntimeMap>{};
    var didReturn = false;
    var outputValues = <String, dynamic>{};
    while (instructionIndex >= 0 &&
        instructionIndex < graph.instructions.length &&
        steps < maxSteps) {
      final instruction = graph.instructions[instructionIndex];
      steps++;
      onStep?.call(instruction, depth);
      final node = instruction.node;
      switch (instruction.kind) {
        case GraphInstructionKind.action:
          final value = await action(
            instruction,
            _config(node, graph.dataWires, runtimeContext),
            runtimeContext,
          );
          final normalizedResult = _normalizeActionResult(value);
          if (normalizedResult != null) {
            results[instruction.nodeId] = normalizedResult;
          }
          final resultMapping = node.data['resultMapping'];
          if (resultMapping is Map) {
            for (final entry in resultMapping.entries) {
              runtimeContext.contextState[entry.value.toString()] = _getPath(
                normalizedResult,
                entry.key.toString(),
              );
            }
          }
          instructionIndex =
              _target(instruction, 'completed') ??
              _target(instruction, 'out') ??
              _first(instruction);
        case GraphInstructionKind.branch:
          final port = node.type == 'if'
              ? (_truthy(
                      evaluateExpression(
                        node.data['condition'],
                        runtimeContext,
                      ),
                    )
                    ? 'then'
                    : 'else')
              : _switchPort(node, runtimeContext);
          instructionIndex = _target(instruction, port) ?? -1;
        case GraphInstructionKind.returnNode:
          outputValues = _returnValues(node.data['outputs'], runtimeContext);
          didReturn = true;
          instructionIndex = -1;
        case GraphInstructionKind.loop:
          instructionIndex = _loopTarget(
            instruction,
            runtimeContext,
            loopState,
          );
        case GraphInstructionKind.breakNode:
          instructionIndex = _target(instruction, 'next') ?? -1;
        case GraphInstructionKind.continueNode:
          instructionIndex =
              _target(instruction, 'continue') ??
              _target(instruction, 'next') ??
              -1;
        case GraphInstructionKind.subgraph:
          final subgraphId = node.data['subgraphId']?.toString();
          final subgraph = subgraphId == null ? null : subgraphs[subgraphId];
          if (subgraph == null) {
            throw StateError('Unknown compiled subgraph: $subgraphId');
          }
          final inputs = _subgraphInputs(
            node,
            subgraph,
            graph.dataWires,
            runtimeContext,
          );
          final nested = await execute(
            graph: subgraph,
            context: EvaluationContext(
              locals: inputs,
              contextState: runtimeContext.contextState,
            ),
            action: action,
            onStep: onStep,
            depth: depth + 1,
            availableSubgraphs: subgraphs,
          );
          results.addAll(nested.nodeResults);
          results[instruction.nodeId] = Map<String, dynamic>.from(
            nested.outputValues,
          );
          runtimeContext.contextState.addAll(nested.contextState);
          instructionIndex =
              _target(instruction, 'completed') ??
              _target(instruction, 'out') ??
              _first(instruction);
        case GraphInstructionKind.passthrough:
          instructionIndex = _target(instruction, 'out') ?? _first(instruction);
      }
    }
    return CompiledGraphExecutionResult(
      completed: instructionIndex < 0,
      steps: steps,
      nodeResults: results,
      contextState: runtimeContext.contextState,
      outputValues: didReturn
          ? {
              ...outputValues,
              ..._boundaryOutputValues(graph.dataWires, runtimeContext),
            }
          : {
              ..._definitionOutputValues(graph.outputs, runtimeContext),
              ..._boundaryOutputValues(graph.dataWires, runtimeContext),
            },
    );
  }
}

RuntimeMap _config(
  GraphNode node,
  List<DataWire> dataWires,
  EvaluationContext context,
) {
  final config = node.data['config'];
  final resolved = config is Map
      ? Map<String, dynamic>.from(config)
      : <String, dynamic>{};
  for (final wire in dataWires.where((wire) => wire.toNode == node.id)) {
    _setPath(
      resolved,
      wire.toPort,
      _resolveWireSource(wire.fromNode, wire.fromPort, context),
    );
  }
  final interpolated = interpolateRuntimeValue(resolved, context);
  return interpolated is Map
      ? Map<String, dynamic>.from(interpolated)
      : resolved;
}

RuntimeMap _subgraphInputs(
  GraphNode node,
  CompiledGraph subgraph,
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
    } else if (rawInputs is Map && rawInputs.containsKey(name)) {
      inputs[name] = _evaluateInput(rawInputs[name], context);
    } else {
      inputs[name] = parameter['default'];
    }
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
  if (fromNode == 'trigger') return _getPath(context.contextState, fromPort);
  if (fromNode.startsWith('__param:')) {
    final value = context.locals[fromNode.substring('__param:'.length)];
    return fromPort == 'value' ? value : _getPath(value, fromPort);
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
  List<JsonMap> definitions,
  EvaluationContext context,
) => {
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

int? _target(GraphInstruction instruction, String port) =>
    instruction.targets[port];
int _first(GraphInstruction instruction) =>
    instruction.targets.values.firstOrNull ?? -1;

String _switchPort(GraphNode node, EvaluationContext context) {
  final value = evaluateExpression(node.data['expression'], context);
  final cases = node.data['cases'];
  if (cases is List) {
    for (final item in cases.whereType<Map>()) {
      if (item['value'] == value) return item['port']?.toString() ?? 'default';
    }
  }
  return 'default';
}

bool _truthy(dynamic value) => value is bool
    ? value
    : value != null && value != 0 && value != '' && value != false;

int _loopTarget(
  GraphInstruction instruction,
  EvaluationContext context,
  Map<String, RuntimeMap> loopState,
) {
  final node = instruction.node;
  final state = loopState[node.id];
  if (node.type == 'while') {
    final iterations = (state?['iterations'] as int?) ?? 0;
    final limit = (node.data['maxIterations'] as num?)?.toInt() ?? 10000;
    if (!_truthy(evaluateExpression(node.data['condition'], context)) ||
        iterations >= limit) {
      loopState.remove(node.id);
      return _target(instruction, 'next') ?? -1;
    }
    loopState[node.id] = {'iterations': iterations + 1};
    return _target(instruction, 'body') ?? -1;
  }
  if (node.type == 'for') {
    final currentState =
        state ??
        <String, dynamic>{
          'current': _number(evaluateExpression(node.data['start'], context)),
          'end': _number(evaluateExpression(node.data['end'], context)),
          'step': _number(evaluateExpression(node.data['step'], context)),
        };
    final current = currentState['current'] as num;
    final end = currentState['end'] as num;
    final step = currentState['step'] as num;
    if (step == 0 || current >= end) {
      loopState.remove(node.id);
      return _target(instruction, 'next') ?? -1;
    }
    context.locals[node.data['variable']?.toString() ?? 'index'] = current;
    currentState['current'] = current + step;
    loopState[node.id] = currentState;
    return _target(instruction, 'body') ?? -1;
  }
  final collection =
      state?['collection'] ??
      evaluateExpression(node.data['collection'], context);
  final index = (state?['index'] as int?) ?? 0;
  if (collection is! List || index >= collection.length) {
    loopState.remove(node.id);
    return _target(instruction, 'next') ?? -1;
  }
  context.locals[node.data['variable']?.toString() ?? 'item'] =
      collection[index];
  final indexVariable = node.data['indexVariable'] as String?;
  if (indexVariable != null) context.locals[indexVariable] = index;
  loopState[node.id] = {'collection': collection, 'index': index + 1};
  return _target(instruction, 'body') ?? -1;
}

num _number(dynamic value) =>
    value is num ? value : num.tryParse('$value') ?? 0;

GraphInstructionKind _kind(String type) => switch (type) {
  'action' => GraphInstructionKind.action,
  'if' || 'switch' => GraphInstructionKind.branch,
  'while' || 'for' || 'forEach' => GraphInstructionKind.loop,
  'return' => GraphInstructionKind.returnNode,
  'break' => GraphInstructionKind.breakNode,
  'continue' => GraphInstructionKind.continueNode,
  'subgraph' || 'subgraphCall' || 'call' => GraphInstructionKind.subgraph,
  _ => GraphInstructionKind.passthrough,
};
