import 'dart:async';

import '../schema/automation.dart';
import 'expression.dart';
import 'execution_trace.dart';
import 'graph_runtime.dart';

import 'graph_program.dart';

final class DartGraphVm {
  DartGraphVm(
    this.program, {
    this.maxIterations = 10000,
    this.maxCallDepth = 32,
    this.onStep,
    this.onNodeEnter,
    this.onNodeExit,
    this.traceSink,
  });

  final DartGraphProgram program;
  final int maxIterations;
  final int maxCallDepth;
  final DartProgramStep? onStep;
  final void Function(String nodeId)? onNodeEnter;
  final void Function(String nodeId)? onNodeExit;
  final ExecutionTraceSink? traceSink;

  int _pc = 0;
  List<dynamic> _locals = [];
  final List<dynamic> _stack = [];
  final List<_DartGraphCallFrame> _callStack = [];
  final Map<String, int> _iterationCounters = {};
  final Map<String, RuntimeMap> _nodeResults = {};
  final Map<String, int> _nodeInvocations = {};
  final Map<String, DateTime> _controlStartedAt = {};
  final Map<String, int> _loopTraceIterations = {};
  final Map<String, int> _localSlotsByName = {};
  late EvaluationContext _context;
  late Map<String, List<({String toPort, DartGraphWireSource source})>>
  _nodeWireInputs;
  bool _didReturn = false;
  Map<String, dynamic> _outputValues = {};
  String? _activeNodeId;
  ExecutionGraphScope _graphScope = const MainGraphScope();

  Future<GraphExecutionResult> execute({
    required EvaluationContext context,
    required DartProgramAction action,
  }) async {
    _locals = List<dynamic>.filled(program.localSlotCount, null);
    _stack.clear();
    _callStack.clear();
    _iterationCounters.clear();
    _nodeResults.clear();
    _nodeInvocations.clear();
    _controlStartedAt.clear();
    _loopTraceIterations.clear();
    _didReturn = false;
    _outputValues = {};
    _graphScope = const MainGraphScope();
    _executedInstructionCount = 0;
    _pc = 0;
    _localSlotsByName
      ..clear()
      ..addEntries(
        program.slotNames.indexed
            .where((entry) => entry.$2.isNotEmpty)
            .map((entry) => MapEntry(entry.$2, entry.$1)),
      );
    _context = EvaluationContext(
      locals: context.locals,
      contextState: context.contextState,
      nodeResults: _nodeResults,
      cancellationToken: context.cancellationToken,
    );
    for (final entry in _localSlotsByName.entries) {
      if (_context.locals.containsKey(entry.key)) {
        _locals[entry.value] = _context.locals[entry.key];
      }
    }
    _nodeWireInputs = _buildNodeWireInputs(program);
    try {
      while (_pc < program.instructions.length) {
        _context.cancellationToken?.throwIfCancelled();
        final instruction = program.instructions[_pc];
        final nodeId = instruction.nodeId;
        final instructionScope = _graphScope;
        if (nodeId != null && nodeId != _activeNodeId) {
          if (_activeNodeId != null) onNodeExit?.call(_activeNodeId!);
          _activeNodeId = nodeId;
          onNodeEnter?.call(nodeId);
        }
        if (nodeId != null && _isControlStartInstruction(instruction)) {
          _startControl(nodeId, instructionScope);
        }
        _publishInstructionEdge(instruction);
        onStep?.call(instruction, _callStack.length);
        final advance = await _step(instruction, action);
        if (nodeId != null &&
            const {
              'break',
              'continue',
              'return',
            }.contains(program.nodeTypes[nodeId])) {
          _completeControl(nodeId, scope: instructionScope);
        }
        if (advance) _pc++;
      }
    } finally {
      if (_activeNodeId != null) {
        onNodeExit?.call(_activeNodeId!);
        _activeNodeId = null;
      }
    }
    return GraphExecutionResult(
      completed: _pc >= program.instructions.length,
      steps: _executedInstructionCount,
      nodeResults: Map.unmodifiable(_nodeResults),
      contextState: Map.unmodifiable(_context.contextState),
      outputValues: _didReturn
          ? {
              ..._outputValues,
              ..._boundaryOutputValues(program.dataWires, _resolveWireSource),
            }
          : {
              ..._definitionOutputValues(program.outputs, _context),
              ..._boundaryOutputValues(program.dataWires, _resolveWireSource),
            },
    );
  }

  int _executedInstructionCount = 0;

  void _publishInstructionEdge(DartGraphInstruction instruction) {
    final from = instruction.edgeFromNodeId;
    final to = instruction.edgeToNodeId;
    final edgeId = instruction.edgeId;
    if (traceSink == null || from == null || to == null || edgeId == null) {
      return;
    }
    final nodeType = program.nodeTypes[from];
    if (nodeType != null && nodeType != 'action') {
      final source = ExecutionNodeRef(nodeId: from, scope: _graphScope);
      // Loop checks and subgraph calls can publish their first semantic edge
      // before an eval/call instruction starts the node. Start lazily here so
      // every control node has a complete lifecycle, including zero-iteration
      // loops.
      _startControl(from, _graphScope);
      final iteration = instruction.edgePort == 'body'
          ? (_loopTraceIterations[source.key] ?? 0) + 1
          : null;
      if (iteration != null) {
        _loopTraceIterations[source.key] = iteration;
      }
      traceSink?.controlPath(
        source,
        instruction.edgePort ?? 'out',
        iteration: iteration,
      );
      if (iteration != null) {
        traceSink?.loopIteration(source, iteration);
      } else if (instruction.edgePort == 'next' ||
          !_isSubgraphNodeType(nodeType)) {
        _completeControl(from, scope: _graphScope);
      }
    }
    traceSink?.edgeTraversed(
      ExecutionEdgeRef(
        edgeId: edgeId,
        from: ExecutionNodeRef(nodeId: from, scope: _graphScope),
        to: ExecutionNodeRef(nodeId: to, scope: _graphScope),
        port: instruction.edgePort,
      ),
    );
  }

  void _startControl(String nodeId, ExecutionGraphScope scope) {
    if (traceSink == null) return;
    final nodeType = program.nodeTypes[nodeId];
    if (nodeType == null || nodeType == 'action') return;
    final ref = ExecutionNodeRef(nodeId: nodeId, scope: scope);
    if (_controlStartedAt.containsKey(ref.key)) return;
    _controlStartedAt[ref.key] = DateTime.now();
    final invocation = (_nodeInvocations[ref.key] ?? 0) + 1;
    _nodeInvocations[ref.key] = invocation;
    traceSink?.nodeStarted(ref, invocation: invocation);
  }

  bool _isSubgraphNodeType(String type) =>
      type == 'subgraphCall' || type == 'subgraph' || type == 'call';

  bool _isControlStartInstruction(DartGraphInstruction instruction) {
    final type = instruction.nodeId == null
        ? null
        : program.nodeTypes[instruction.nodeId];
    if (type == null || type == 'action') return false;
    return switch (instruction.op) {
      DartGraphOpCode.eval => true,
      DartGraphOpCode.call => true,
      DartGraphOpCode.jump || DartGraphOpCode.ret =>
        type == 'break' || type == 'continue' || type == 'return',
      _ => false,
    };
  }

  void _completeControl(
    String nodeId, {
    required ExecutionGraphScope scope,
    Duration? duration,
    int? invocation,
  }) {
    if (traceSink == null) return;
    final ref = ExecutionNodeRef(nodeId: nodeId, scope: scope);
    final started = _controlStartedAt.remove(ref.key);
    if (started == null) return;
    traceSink?.nodeCompleted(
      ref,
      invocation: invocation ?? _nodeInvocations[ref.key],
      duration: duration ?? DateTime.now().difference(started),
    );
  }

  Future<bool> _step(
    DartGraphInstruction instruction,
    DartProgramAction action,
  ) async {
    _executedInstructionCount++;
    switch (instruction.op) {
      case DartGraphOpCode.exec:
        await _execAction(instruction, action);
        return true;
      case DartGraphOpCode.jump:
        _pc = instruction.arg0 ?? -1;
        return false;
      case DartGraphOpCode.jumpIf:
        if (_truthy(_stack.removeLast())) {
          _pc = instruction.arg0 ?? -1;
          return false;
        }
        return true;
      case DartGraphOpCode.jumpIfNot:
        if (!_truthy(_stack.removeLast())) {
          _pc = instruction.arg0 ?? -1;
          return false;
        }
        return true;
      case DartGraphOpCode.eval:
        if (instruction.nodeId != null &&
            program.loopNodeIds.contains(instruction.nodeId)) {
          _checkIterationLimit(instruction.nodeId);
        }
        _syncLocalsToContext();
        _stack.add(evaluateExpression(instruction.arg1, _context));
        return true;
      case DartGraphOpCode.store:
        _locals[instruction.arg0 ?? 0] = _stack.removeLast();
        _syncSlotToContext(instruction.arg0 ?? 0);
        return true;
      case DartGraphOpCode.load:
        _stack.add(_locals[instruction.arg0 ?? 0]);
        return true;
      case DartGraphOpCode.loopInit:
      case DartGraphOpCode.iterInit:
        return true;
      case DartGraphOpCode.loopCheck:
        _checkIterationLimit(instruction.nodeId);
        final counter = _locals[instruction.arg0 ?? 0];
        final end = _locals[instruction.arg1 as int? ?? 0];
        if (counter is! num || end is! num) {
          throw StateError(
            'Loop bounds must be numeric at ${instruction.nodeId}.',
          );
        }
        if (counter >= end) {
          _pc = instruction.arg2 as int? ?? -1;
          return false;
        }
        return true;
      case DartGraphOpCode.loopStep:
        _syncLocalsToContext();
        final current = _asNumber(_locals[instruction.arg0 ?? 0]);
        final step = _asNumber(evaluateExpression(instruction.arg1, _context));
        if (!current.isFinite || !step.isFinite) {
          throw StateError(
            'Loop step must be numeric at ${instruction.nodeId}.',
          );
        }
        _locals[instruction.arg0 ?? 0] = current + step;
        _syncSlotToContext(instruction.arg0 ?? 0);
        return true;
      case DartGraphOpCode.iterNext:
        _checkIterationLimit(instruction.nodeId);
        final args = instruction.arg1 as DartGraphIterNextArgs;
        final collection = _locals[args.collSlot];
        final index = _locals[args.indexSlot];
        if (collection is! List ||
            index is! int ||
            index >= collection.length) {
          _pc = instruction.arg2 as int? ?? -1;
          return false;
        }
        _locals[args.itemSlot] = collection[index];
        _syncSlotToContext(args.itemSlot);
        return true;
      case DartGraphOpCode.call:
        _execCall(instruction);
        return false;
      case DartGraphOpCode.ret:
        _execReturn(instruction);
        return false;
      case DartGraphOpCode.yieldControl:
        await _yieldToEventLoop();
        return true;
      case DartGraphOpCode.halt:
        _pc = program.instructions.length;
        return false;
    }
  }

  Future<void> _execAction(
    DartGraphInstruction instruction,
    DartProgramAction action,
  ) async {
    final nodeIndex = instruction.arg0 ?? -1;
    if (nodeIndex < 0 || nodeIndex >= program.actionNodes.length) return;
    final node = program.actionNodes[nodeIndex];
    final nodeRef = ExecutionNodeRef(nodeId: node.id, scope: _graphScope);
    final invocation = (_nodeInvocations[nodeRef.key] ?? 0) + 1;
    _nodeInvocations[nodeRef.key] = invocation;
    final stopwatch = Stopwatch()..start();
    traceSink?.nodeStarted(nodeRef, invocation: invocation);
    _syncLocalsToContext();
    _context.cancellationToken?.throwIfCancelled();
    late final Object? result;
    try {
      result = await action(node, _resolveActionConfig(node), _context);
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
    _context.cancellationToken?.throwIfCancelled();
    final normalized = _normalizeActionResult(result);
    if (normalized != null) _nodeResults[node.id] = normalized;
    final mapping = node.data['resultMapping'];
    if (mapping is Map) {
      for (final entry in mapping.entries) {
        _context.contextState[entry.value.toString()] = _getPath(
          normalized,
          entry.key.toString(),
        );
      }
    }
  }

  RuntimeMap _resolveActionConfig(GraphNode node) {
    final raw = node.data['config'];
    final config = raw is Map
        ? _cloneValue(raw) as RuntimeMap
        : <String, dynamic>{};
    for (final wire in _nodeWireInputs[node.id] ?? const []) {
      _setPath(config, wire.toPort, _resolveWireSource(wire.source));
    }
    final interpolated = interpolateRuntimeValue(config, _context);
    return interpolated is Map
        ? Map<String, dynamic>.from(interpolated)
        : config;
  }

  void _execCall(DartGraphInstruction instruction) {
    if (_callStack.length >= maxCallDepth) {
      throw StateError('Maximum graph recursion depth exceeded: $maxCallDepth');
    }
    final subgraphIndex = instruction.arg0 ?? -1;
    if (subgraphIndex < 0 || subgraphIndex >= program.subgraphs.length) {
      throw StateError('Unknown compiled subgraph.');
    }
    final subgraph = program.subgraphs[subgraphIndex];
    final callNodeId = instruction.nodeId;
    final callScope = _graphScope;
    final callInvocation = callNodeId == null
        ? null
        : _nodeInvocations[ExecutionNodeRef(
            nodeId: callNodeId,
            scope: callScope,
          ).key];
    final callStartedAt = callNodeId == null
        ? null
        : _controlStartedAt[ExecutionNodeRef(
            nodeId: callNodeId,
            scope: callScope,
          ).key];
    if (callNodeId != null) {
      traceSink?.subgraphEntered(
        ExecutionNodeRef(nodeId: callNodeId, scope: callScope),
        subgraph.id,
        depth: _callStack.length + 1,
      );
    }
    _callStack.add(
      _DartGraphCallFrame(
        returnPc: _pc + 1,
        localSnapshot: List<dynamic>.of(_locals),
        callNodeId: callNodeId,
        localSlotsByName: Map<String, int>.from(_localSlotsByName),
        contextLocals: Map<String, dynamic>.from(_context.locals),
        graphScope: callScope,
        subgraphId: subgraph.id,
        callDepth: _callStack.length + 1,
        callInvocation: callInvocation,
        callStartedAt: callStartedAt,
      ),
    );
    final inputs = instruction.arg1 is Map
        ? Map<String, dynamic>.from(instruction.arg1 as Map)
        : const <String, dynamic>{};
    final wires = _nodeWireInputs[callNodeId ?? ''] ?? const [];
    final wired = {for (final wire in wires) wire.toPort: wire.source};
    final parameterValues = <String, dynamic>{};
    for (var index = 0; index < subgraph.paramNames.length; index++) {
      final name = subgraph.paramNames[index];
      if (name.isEmpty) continue;
      parameterValues[name] = wired[name] != null
          ? _resolveWireSource(wired[name]!)
          : inputs.containsKey(name)
          ? _evaluateInput(inputs[name])
          : null;
    }
    _localSlotsByName
      ..clear()
      ..addAll(subgraph.localSlotsByName);
    _context = EvaluationContext(
      locals: const {},
      contextState: _context.contextState,
      nodeResults: _nodeResults,
      cancellationToken: _context.cancellationToken,
    );
    _graphScope = SubgraphScope(subgraph.id);
    for (var index = 0; index < subgraph.paramNames.length; index++) {
      final name = subgraph.paramNames[index];
      if (name.isEmpty) continue;
      final value = parameterValues[name];
      _locals[subgraph.paramSlots[index]] = value;
      _syncSlotToContext(subgraph.paramSlots[index]);
    }
    _pc = subgraph.entryPc;
  }

  void _execReturn(DartGraphInstruction instruction) {
    final frame = _callStack.isEmpty ? null : _callStack.removeLast();
    final expressions = instruction.arg1 is Map
        ? Map<String, dynamic>.from(instruction.arg1 as Map)
        : const <String, dynamic>{};
    final outputs = <String, dynamic>{
      for (final entry in expressions.entries)
        entry.key: _evaluateInput(entry.value),
    };
    if (frame == null) {
      _outputValues = outputs;
      _didReturn = true;
      _pc = program.instructions.length;
      return;
    }
    if (frame.callNodeId != null && frame.subgraphId != null) {
      final callNode = ExecutionNodeRef(
        nodeId: frame.callNodeId!,
        scope: frame.graphScope,
      );
      traceSink?.subgraphExited(
        callNode,
        frame.subgraphId!,
        depth: frame.callDepth,
        duration: frame.callStartedAt == null
            ? Duration.zero
            : DateTime.now().difference(frame.callStartedAt!),
      );
      _completeControl(
        frame.callNodeId!,
        scope: frame.graphScope,
        duration: frame.callStartedAt == null
            ? Duration.zero
            : DateTime.now().difference(frame.callStartedAt!),
        invocation: frame.callInvocation,
      );
    }
    _locals = frame.localSnapshot;
    _localSlotsByName
      ..clear()
      ..addAll(frame.localSlotsByName);
    _graphScope = frame.graphScope;
    _context = EvaluationContext(
      locals: frame.contextLocals,
      contextState: _context.contextState,
      nodeResults: _nodeResults,
      cancellationToken: _context.cancellationToken,
    );
    if (frame.callNodeId != null) _nodeResults[frame.callNodeId!] = outputs;
    _pc = frame.returnPc;
  }

  dynamic _evaluateInput(Object? input) {
    if (input is Map && input['type'] is String) {
      _syncLocalsToContext();
      return evaluateExpression(input, _context);
    }
    return input;
  }

  dynamic _resolveWireSource(DartGraphWireSource source) {
    if (program.contextSourceNodeIds.contains(source.fromNodeId)) {
      return _getPath(_context.contextState, source.fromPort);
    }
    if (source.fromNodeId.startsWith('__param:')) {
      final name = source.fromNodeId.substring('__param:'.length);
      final slot = _localSlotsByName[name];
      final value = slot == null ? null : _locals[slot];
      return source.fromPort == 'value'
          ? value
          : _getPath(value, source.fromPort);
    }
    return _getPath(_nodeResults[source.fromNodeId], source.fromPort);
  }

  void _checkIterationLimit(String? nodeId) {
    final key = nodeId ?? '__global';
    final next = (_iterationCounters[key] ?? 0) + 1;
    _iterationCounters[key] = next;
    final limit = program.loopLimits[key] ?? maxIterations;
    if (next > limit) {
      throw StateError(
        'Loop iteration limit ($limit) exceeded at ${nodeId ?? 'unknown'}.',
      );
    }
  }

  Future<void> _yieldToEventLoop() async {
    _context.cancellationToken?.throwIfCancelled();
    await Future<void>.delayed(Duration.zero);
    _context.cancellationToken?.throwIfCancelled();
  }

  void _syncLocalsToContext() {
    for (final entry in _localSlotsByName.entries) {
      final value = _locals[entry.value];
      if (value != null) _context.locals[entry.key] = value;
    }
  }

  void _syncSlotToContext(int slot) {
    for (final entry in _localSlotsByName.entries) {
      if (entry.value == slot) _context.locals[entry.key] = _locals[slot];
    }
  }
}

final class _DartGraphCallFrame {
  const _DartGraphCallFrame({
    required this.returnPc,
    required this.localSnapshot,
    required this.callNodeId,
    required this.localSlotsByName,
    required this.contextLocals,
    required this.graphScope,
    required this.subgraphId,
    required this.callDepth,
    required this.callInvocation,
    required this.callStartedAt,
  });

  final int returnPc;
  final List<dynamic> localSnapshot;
  final String? callNodeId;
  final Map<String, int> localSlotsByName;
  final Map<String, dynamic> contextLocals;
  final ExecutionGraphScope graphScope;
  final String? subgraphId;
  final int callDepth;
  final int? callInvocation;
  final DateTime? callStartedAt;
}

Map<String, List<({String toPort, DartGraphWireSource source})>>
_buildNodeWireInputs(DartGraphProgram program) {
  final result =
      <String, List<({String toPort, DartGraphWireSource source})>>{};
  final nodeIds = program.wireTargetNodeIds.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final entry in program.wireMap.entries) {
    final nodeId = nodeIds.firstWhere(
      (id) => entry.key.startsWith('$id:'),
      orElse: () => '',
    );
    if (nodeId.isEmpty) continue;
    final toPort = entry.key.substring(nodeId.length + 1);
    if (toPort.isEmpty) continue;
    result.putIfAbsent(nodeId, () => []).add((
      toPort: toPort,
      source: entry.value,
    ));
  }
  return result;
}

RuntimeMap? _normalizeActionResult(Object? result) {
  if (result is Map) {
    return {
      for (final entry in result.entries) entry.key.toString(): entry.value,
    };
  }
  return result == null ? null : {'_result': result};
}

Object? _cloneValue(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): _cloneValue(entry.value),
    };
  }
  if (value is List) return value.map(_cloneValue).toList();
  return value;
}

void _setPath(RuntimeMap target, String path, Object? value) {
  final parts = path.split('.').where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) return;
  var current = target;
  for (final part in parts.take(parts.length - 1)) {
    final next = current[part];
    if (next is Map) {
      final copy = Map<String, dynamic>.from(next);
      current[part] = copy;
      current = copy;
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

Map<String, dynamic> _definitionOutputValues(
  List<JsonMap> definitions,
  EvaluationContext context,
) => {
  for (final definition in definitions)
    if (definition['name'] is String && definition['expression'] != null)
      definition['name'].toString(): evaluateExpression(
        definition['expression'],
        context,
      ),
};

Map<String, dynamic> _boundaryOutputValues(
  List<DataWire> wires,
  dynamic Function(DartGraphWireSource source) resolveSource,
) => {
  for (final wire in wires.where((wire) => wire.toNode.startsWith('__output:')))
    wire.toNode.substring('__output:'.length): resolveSource(
      DartGraphWireSource(fromNodeId: wire.fromNode, fromPort: wire.fromPort),
    ),
};

num _asNumber(Object? value) =>
    value is num ? value : num.tryParse('$value') ?? double.nan;

bool _truthy(Object? value) => value is bool
    ? value
    : value != null && value != 0 && value != '' && value != false;
