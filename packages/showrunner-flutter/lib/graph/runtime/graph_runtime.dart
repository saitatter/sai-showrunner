import 'automation_runtime_projection.dart';
import 'runtime_values.dart';
import '../../plugins/registry/plugin_registry.dart';
import '../../runtime/expression.dart';
import '../../runtime/execution_trace.dart';

typedef GraphAction =
    Future<Object?> Function(
      RuntimeNode node,
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
    required RuntimeGraph graph,
    required EvaluationContext context,
    required DartPluginRegistry registry,
    List<RuntimeValueBinding> dataWires = const <RuntimeValueBinding>[],
    List<RuntimeSubgraph> subgraphs = const <RuntimeSubgraph>[],
    String? entryNodeId,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
    ExecutionTraceSink? traceSink,
    ExecutionGraphScope graphScope = const MainGraphScope(),
  }) {
    return execute(
      graph: graph,
      context: EvaluationContext(
        locals: context.locals,
        contextState: {...registry.stateContext(), ...context.contextState},
        cancellationToken: context.cancellationToken,
      ),
      dataWires: dataWires,
      subgraphs: {for (final subgraph in subgraphs) subgraph.id: subgraph},
      entryNodeId: entryNodeId,
      onNodeEnter: onNodeEnter,
      onNodeExit: onNodeExit,
      traceSink: traceSink,
      graphScope: graphScope,
      action: (node, config, runtimeContext) => registry.invokeAction(
        node.data['plugin'] as String,
        node.data['action'] as String,
        config,
        context: runtimeContext,
      ),
    );
  }

  Future<GraphExecutionResult> execute({
    required RuntimeGraph graph,
    required EvaluationContext context,
    required GraphAction action,
    List<RuntimeValueBinding> dataWires = const <RuntimeValueBinding>[],
    Map<String, RuntimeSubgraph> subgraphs = const <String, RuntimeSubgraph>{},
    List<JsonMap>? outputDefinitions,
    String? entryNodeId,
    void Function(String nodeId)? onNodeEnter,
    void Function(String nodeId)? onNodeExit,
    ExecutionTraceSink? traceSink,
    ExecutionGraphScope graphScope = const MainGraphScope(),
    int depth = 0,
    Map<String, int>? invocationCounts,
  }) async {
    context.cancellationToken?.throwIfCancelled();
    if (depth > maxDepth) {
      throw StateError('Maximum graph recursion depth exceeded: $maxDepth');
    }
    final nodes = {for (final node in graph.nodes) node.id: node};
    final outgoing = <String, List<RuntimeControlEdge>>{};
    for (final edge in graph.edges) {
      outgoing.putIfAbsent(edge.from, () => []).add(edge);
    }
    final results = <String, RuntimeMap>{};
    final loopState = <String, dynamic>{};
    final runtimeContext = EvaluationContext(
      locals: Map<String, dynamic>.from(context.locals),
      contextState: Map<String, dynamic>.from(context.contextState),
      nodeResults: results,
      cancellationToken: context.cancellationToken,
    );
    graph.projection.values.seedScope(graph.space.id, runtimeContext);
    var current = entryNodeId ?? graph.entryNodeId;
    var steps = 0;
    var didReturn = false;
    var outputValues = <String, dynamic>{};
    final invocations = invocationCounts ?? <String, int>{};
    final continuations = <({String owner, String resume, bool loop})>[];
    final activeControls = <String, _ControlExecutionState>{};

    void beginControl(RuntimeNode node) {
      if (traceSink == null) return;
      if (node.type == 'action') return;
      final ref = ExecutionNodeRef(nodeId: node.id, scope: graphScope);
      if (activeControls.containsKey(ref.key)) return;
      final invocation = (invocations[ref.key] ?? 0) + 1;
      invocations[ref.key] = invocation;
      final state = _ControlExecutionState(
        node: ref,
        invocation: invocation,
        startedAt: DateTime.now(),
      );
      activeControls[ref.key] = state;
      traceSink.nodeStarted(ref, invocation: invocation);
    }

    void markControlPath(RuntimeNode node, String port, {int? iteration}) {
      traceSink?.controlPath(
        ExecutionNodeRef(nodeId: node.id, scope: graphScope),
        port,
        iteration: iteration,
      );
    }

    void markLoopIteration(RuntimeNode node, int iteration) {
      traceSink?.loopIteration(
        ExecutionNodeRef(nodeId: node.id, scope: graphScope),
        iteration,
      );
    }

    void completeControl(RuntimeNode node) {
      final ref = ExecutionNodeRef(nodeId: node.id, scope: graphScope);
      final state = activeControls.remove(ref.key);
      if (state == null) return;
      traceSink?.nodeCompleted(
        ref,
        invocation: state.invocation,
        duration: DateTime.now().difference(state.startedAt),
      );
    }

    void follow(RuntimeControlEdge? edge) {
      if (edge != null) {
        traceSink?.edgeTraversed(
          ExecutionEdgeRef(
            edgeId: edge.id,
            from: ExecutionNodeRef(nodeId: edge.from, scope: graphScope),
            to: ExecutionNodeRef(nodeId: edge.to, scope: graphScope),
            port: edge.port,
          ),
        );
      }
      var target = edge?.to;
      if (target != null) {
        final matched = continuations.lastIndexWhere(
          (item) => item.resume == target,
        );
        if (matched >= 0) {
          final frame = continuations[matched];
          continuations.removeRange(
            matched + (frame.loop ? 1 : 0),
            continuations.length,
          );
        }
      } else if (continuations.isNotEmpty) {
        final frame = continuations.removeLast();
        if (frame.loop) continuations.add(frame);
        target = frame.resume;
      }
      current = target ?? '';
    }

    while (current.isNotEmpty && steps < maxSteps) {
      runtimeContext.cancellationToken?.throwIfCancelled();
      final node = nodes[current];
      if (node == null) break;
      steps++;
      onNodeEnter?.call(node.id);
      beginControl(node);
      final edges = outgoing[node.id] ?? const <RuntimeControlEdge>[];
      switch (node.type) {
        case 'action':
          final nodeRef = ExecutionNodeRef(nodeId: node.id, scope: graphScope);
          final invocation = (invocations[nodeRef.key] ?? 0) + 1;
          invocations[nodeRef.key] = invocation;
          final stopwatch = Stopwatch()..start();
          traceSink?.nodeStarted(nodeRef, invocation: invocation);
          late final Object? result;
          try {
            result = await action(
              node,
              _config(node, dataWires, runtimeContext),
              runtimeContext,
            );
            traceSink?.nodeResult(nodeRef, result, invocation: invocation);
            traceSink?.nodeCompleted(
              nodeRef,
              invocation: invocation,
              duration: stopwatch.elapsed,
            );
          } catch (error, stackTrace) {
            traceSink?.nodeFailed(
              nodeRef,
              error,
              stackTrace: stackTrace,
              invocation: invocation,
              duration: stopwatch.elapsed,
            );
            rethrow;
          }
          runtimeContext.cancellationToken?.throwIfCancelled();
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
          follow(
            _next(edges, 'completed') ??
                _next(edges, 'out') ??
                edges.firstOrNull,
          );
        case 'if':
          final condition = _truthy(
            node.projection.values.input(
              node.id,
              'condition',
              node.data['condition'],
              runtimeContext,
            ),
          );
          final port = condition ? 'then' : 'else';
          markControlPath(node, port);
          completeControl(node);
          final join = _next(edges, 'next');
          if (join != null) {
            continuations.add((owner: node.id, resume: join.to, loop: false));
          }
          follow(_next(edges, port));
        case 'while':
          final iterations = (loopState[node.id] as int?) ?? 0;
          final condition = _truthy(
            node.projection.values.input(
              node.id,
              'condition',
              node.data['condition'],
              runtimeContext,
            ),
          );
          final limit =
              (node.data['maxIterations'] as num?)?.toInt() ?? maxSteps;
          if (condition && iterations >= limit) {
            throw StateError(
              'Loop iteration limit ($limit) exceeded at ${node.id}.',
            );
          }
          if (!condition) {
            loopState.remove(node.id);
            continuations.removeWhere((item) => item.owner == node.id);
            markControlPath(node, 'next');
            completeControl(node);
            follow(_next(edges, 'next'));
          } else {
            loopState[node.id] = iterations + 1;
            results[node.id] = {'iteration': iterations};
            final iteration = iterations + 1;
            markLoopIteration(node, iteration);
            markControlPath(node, 'body', iteration: iteration);
            if (!continuations.any(
              (item) => item.owner == node.id && item.loop,
            )) {
              continuations.add((owner: node.id, resume: node.id, loop: true));
            }
            follow(_next(edges, 'body'));
          }
        case 'for':
          final state = loopState[node.id] as RuntimeMap?;
          final loop =
              state ??
              <String, dynamic>{
                'current': _number(
                  node.projection.values.input(
                    node.id,
                    'start',
                    node.data['start'],
                    runtimeContext,
                  ),
                ),
                'end': _number(
                  node.projection.values.input(
                    node.id,
                    'end',
                    node.data['end'],
                    runtimeContext,
                  ),
                ),
                'step': _number(
                  node.projection.values.input(
                    node.id,
                    'step',
                    node.data['step'],
                    runtimeContext,
                  ),
                ),
              };
          if (state == null) loopState[node.id] = loop;
          if (loop['step'] == 0) {
            throw StateError('Loop step must be nonzero at ${node.id}.');
          }
          if (loop['step'] > 0
              ? loop['current'] >= loop['end']
              : loop['current'] <= loop['end']) {
            loopState.remove(node.id);
            continuations.removeWhere((item) => item.owner == node.id);
            markControlPath(node, 'next');
            completeControl(node);
            follow(_next(edges, 'next'));
          } else {
            final iteration = ((loop['iteration'] as int?) ?? 0) + 1;
            final limit =
                (node.data['maxIterations'] as num?)?.toInt() ?? maxSteps;
            if (iteration > limit) {
              throw StateError(
                'Loop iteration limit ($limit) exceeded at ${node.id}.',
              );
            }
            loop['iteration'] = iteration;
            runtimeContext.locals[node.data['variable'] as String? ?? 'index'] =
                loop['current'];
            results[node.id] = {'index': loop['current']};
            loop['current'] = loop['current'] + loop['step'];
            markLoopIteration(node, iteration);
            markControlPath(node, 'body', iteration: iteration);
            if (!continuations.any(
              (item) => item.owner == node.id && item.loop,
            )) {
              continuations.add((owner: node.id, resume: node.id, loop: true));
            }
            follow(_next(edges, 'body'));
          }
        case 'forEach':
          final state = loopState[node.id] as RuntimeMap?;
          final collection =
              state?['collection'] ??
              node.projection.values.input(
                node.id,
                'collection',
                node.data['collection'],
                runtimeContext,
              );
          final index = (state?['index'] as int?) ?? 0;
          if (state == null) {
            loopState[node.id] = {'collection': collection, 'index': 0};
          }
          if (collection is! List || index >= collection.length) {
            loopState.remove(node.id);
            continuations.removeWhere((item) => item.owner == node.id);
            markControlPath(node, 'next');
            completeControl(node);
            follow(_next(edges, 'next'));
          } else {
            runtimeContext.locals[node.data['variable'] as String? ?? 'item'] =
                collection[index];
            results[node.id] = {'item': collection[index], 'index': index};
            final indexVariable = node.data['indexVariable'] as String?;
            if (indexVariable != null) {
              runtimeContext.locals[indexVariable] = index;
            }
            loopState[node.id] = {'collection': collection, 'index': index + 1};
            final iteration = index + 1;
            final limit =
                (node.data['maxIterations'] as num?)?.toInt() ?? maxSteps;
            if (iteration > limit) {
              throw StateError(
                'Loop iteration limit ($limit) exceeded at ${node.id}.',
              );
            }
            markLoopIteration(node, iteration);
            markControlPath(node, 'body', iteration: iteration);
            if (!continuations.any(
              (item) => item.owner == node.id && item.loop,
            )) {
              continuations.add((owner: node.id, resume: node.id, loop: true));
            }
            follow(_next(edges, 'body'));
          }
        case 'break':
          final index = continuations.lastIndexWhere((item) => item.loop);
          if (index < 0) {
            throw StateError('Break outside a loop at ${node.id}.');
          }
          final loop = nodes[continuations[index].owner]!;
          continuations.removeRange(index, continuations.length);
          loopState.remove(loop.id);
          completeControl(node);
          completeControl(loop);
          follow(_next(outgoing[loop.id] ?? [], 'next'));
        case 'continue':
          final index = continuations.lastIndexWhere((item) => item.loop);
          if (index < 0) {
            throw StateError('Continue outside a loop at ${node.id}.');
          }
          continuations.removeRange(index + 1, continuations.length);
          completeControl(node);
          follow(null);
        case 'switch':
          final value = node.projection.values.input(
            node.id,
            'expression',
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
          final selectedPort = port ?? 'default';
          markControlPath(node, selectedPort);
          completeControl(node);
          final join = _next(edges, 'next');
          if (join != null) {
            continuations.add((owner: node.id, resume: join.to, loop: false));
          }
          follow(_next(edges, selectedPort));
        case 'return':
          outputValues = node.projection.values.outputs(
            node.id,
            node.data['outputs'] is Map ? node.data['outputs'] as Map : {},
            runtimeContext,
          );
          didReturn = true;
          completeControl(node);
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
          final callRef = ExecutionNodeRef(nodeId: node.id, scope: graphScope);
          if (subgraphId != null) {
            traceSink?.subgraphEntered(callRef, subgraphId, depth: depth + 1);
          }
          final nested = await execute(
            graph: subgraph.body,
            action: action,
            dataWires: subgraph.dataWires,
            subgraphs: subgraphs,
            entryNodeId: subgraph.entryNodeId,
            outputDefinitions: subgraph.outputs,
            context: EvaluationContext(
              locals: inputs,
              contextState: runtimeContext.contextState,
              cancellationToken: runtimeContext.cancellationToken,
            ),
            onNodeEnter: onNodeEnter,
            onNodeExit: onNodeExit,
            traceSink: traceSink,
            graphScope: SubgraphScope(subgraph.id),
            depth: depth + 1,
            invocationCounts: invocations,
          );
          runtimeContext.cancellationToken?.throwIfCancelled();
          final callState = activeControls[callRef.key];
          if (subgraphId != null) {
            traceSink?.subgraphExited(
              callRef,
              subgraphId,
              depth: depth + 1,
              duration: callState == null
                  ? Duration.zero
                  : DateTime.now().difference(callState.startedAt),
            );
          }
          completeControl(node);

          results[node.id] = Map<String, dynamic>.from(nested.outputValues);
          runtimeContext.contextState.addAll(nested.contextState);
          follow(
            _next(edges, 'completed') ??
                _next(edges, 'out') ??
                edges.firstOrNull,
          );
        default:
          completeControl(node);
          follow(edges.firstOrNull);
      }
      onNodeExit?.call(node.id);
    }
    if (current.isNotEmpty) {
      throw StateError('Graph step limit ($maxSteps) exceeded.');
    }
    return GraphExecutionResult(
      completed: current.isEmpty,
      steps: steps,
      nodeResults: results,
      contextState: runtimeContext.contextState,
      outputValues: didReturn
          ? {...outputValues}
          : {..._definitionOutputValues(outputDefinitions, runtimeContext)},
    );
  }
}

RuntimeControlEdge? _next(List<RuntimeControlEdge> edges, String port) =>
    edges.where((edge) => edge.port == port).firstOrNull;

RuntimeMap _config(
  RuntimeNode node,
  List<RuntimeValueBinding> dataWires,
  EvaluationContext context,
) {
  final config = node.data['config'];
  final resolved = config is Map ? _cloneMap(config) : <String, dynamic>{};
  for (final wire in dataWires.where((wire) => wire.toNode == node.id)) {
    final source = node.projection.values.resolve(
      wire.fromNode,
      wire.fromPort,
      context,
    );
    _setPath(resolved, wire.toPort, source);
  }
  final interpolated = interpolateRuntimeValue(resolved, context);
  return interpolated is Map
      ? Map<String, dynamic>.from(interpolated)
      : resolved;
}

RuntimeMap _subgraphInputs(
  RuntimeNode node,
  RuntimeSubgraph subgraph,
  List<RuntimeValueBinding> dataWires,
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
      inputs[name] = node.projection.values.resolve(
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

final class _ControlExecutionState {
  const _ControlExecutionState({
    required this.node,
    required this.invocation,
    required this.startedAt,
  });

  final ExecutionNodeRef node;
  final int invocation;
  final DateTime startedAt;
}

dynamic _evaluateInput(dynamic input, EvaluationContext context) {
  if (input is Map && input['type'] is String) {
    return evaluateExpression(input, context);
  }
  return input;
}

Map<String, dynamic> _definitionOutputValues(
  List<JsonMap>? definitions,
  EvaluationContext context,
) => definitions == null
    ? <String, dynamic>{}
    : {
        for (final definition in definitions)
          if (definition['name'] is String)
            definition['name'].toString(): evaluateRuntimeInput(
              definition['expression'],
              context,
            ),
      };

bool _truthy(dynamic value) => value is bool
    ? value
    : value != null && value != 0 && value != '' && value != false;
num _number(dynamic value) {
  final number = value is num ? value : num.tryParse('$value');
  if (number == null || !number.isFinite) {
    throw StateError('Loop bounds and step must be finite numbers.');
  }
  return number;
}

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
