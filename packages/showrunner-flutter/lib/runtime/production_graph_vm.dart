import 'dart:async';

import '../schema/automation.dart';
import 'expression.dart';
import 'graph_runtime.dart';

/// The instruction set used by the production graph execution path.
///
/// Keeping this list explicit makes the Flutter runtime mechanically
/// comparable with the reference GraphCompiler/GraphVM implementation.
enum DartGraphOpCode {
  exec,
  jump,
  jumpIf,
  jumpIfNot,
  eval,
  store,
  load,
  loopInit,
  loopCheck,
  loopStep,
  iterInit,
  iterNext,
  call,
  ret,
  yieldControl,
  halt,
}

final class DartGraphInstruction {
  const DartGraphInstruction({
    required this.op,
    this.nodeId,
    this.arg0,
    this.arg1,
    this.arg2,
  });

  final DartGraphOpCode op;
  final String? nodeId;
  final int? arg0;
  final Object? arg1;
  final Object? arg2;
}

final class DartGraphIterNextArgs {
  const DartGraphIterNextArgs({
    required this.itemSlot,
    required this.indexSlot,
    required this.collSlot,
  });

  final int itemSlot;
  final int indexSlot;
  final int collSlot;
}

final class DartCompiledSubgraphV2 {
  const DartCompiledSubgraphV2({
    required this.id,
    required this.name,
    required this.entryPc,
    required this.paramSlots,
    required this.paramNames,
    required this.localSlotsByName,
  });

  final String id;
  final String name;
  final int entryPc;
  final List<int> paramSlots;
  final List<String> paramNames;
  final Map<String, int> localSlotsByName;
}

final class DartGraphWireSource {
  const DartGraphWireSource({required this.fromNodeId, required this.fromPort});

  final String fromNodeId;
  final String fromPort;
}

final class DartGraphProgram {
  const DartGraphProgram({
    required this.instructions,
    required this.actionNodes,
    required this.subgraphs,
    required this.localSlotCount,
    required this.slotNames,
    required this.wireMap,
    required this.contextSourceNodeIds,
    required this.wireTargetNodeIds,
    required this.dataWires,
    required this.outputs,
    required this.loopLimits,
    required this.loopNodeIds,
  });

  final List<DartGraphInstruction> instructions;
  final List<GraphNode> actionNodes;
  final List<DartCompiledSubgraphV2> subgraphs;
  final int localSlotCount;
  final List<String> slotNames;
  final Map<String, DartGraphWireSource> wireMap;
  final List<String> contextSourceNodeIds;
  final List<String> wireTargetNodeIds;
  final List<DataWire> dataWires;
  final List<JsonMap> outputs;
  final Map<String, int> loopLimits;
  final Set<String> loopNodeIds;
}

typedef DartProgramAction =
    Future<Object?> Function(
      GraphNode node,
      RuntimeMap config,
      EvaluationContext context,
    );

typedef DartProgramStep =
    void Function(DartGraphInstruction instruction, int depth);

final class DartProductionGraphCompiler {
  DartProductionGraphCompiler({this.yieldInterval = 64});

  final int yieldInterval;
  final List<DartGraphInstruction> _instructions = [];
  final List<GraphNode> _actionNodes = [];
  final Map<String, int> _localSlots = {};
  final Map<String, int> _slotAliases = {};
  final Map<String, List<GraphEdge>> _edgeMap = {};
  final Map<String, GraphNode> _nodeMap = {};
  final Map<String, int> _subgraphIndexById = {};
  final Set<String> _contextSourceNodeIds = {'trigger'};
  final Map<String, int> _nodePc = {};
  final Map<String, int> _loopRepeatLabels = {};
  final Map<String, int> _loopLimits = {};
  final Set<String> _loopNodeIds = {};
  final List<int> _loopExitStack = [];
  final List<int> _loopHeaderStack = [];
  final List<int> _loopContinueStack = [];
  final Map<int, int> _labels = {};
  final List<({int instructionIndex, int labelId})> _pendingJumps = [];
  int _nextSlot = 0;
  int _nextLabel = 0;

  DartGraphProgram compileAutomation(
    AutomationData automation, {
    String? entryNodeId,
  }) => compile(
    automation.graph,
    subgraphs: automation.subgraphs,
    dataWires: automation.dataWires,
    triggerNodes: automation.triggerNodes,
    entryNodeId: entryNodeId,
  );

  DartGraphProgram compile(
    AutomationGraph graph, {
    List<SubgraphDefinition> subgraphs = const [],
    List<DataWire> dataWires = const [],
    List<JsonMap> triggerNodes = const [],
    String? entryNodeId,
  }) {
    _reset();
    _contextSourceNodeIds.addAll(
      triggerNodes
          .map((node) => node['id'])
          .whereType<String>()
          .where((id) => id.isNotEmpty),
    );
    _subgraphIndexById.addAll({
      for (var index = 0; index < subgraphs.length; index++)
        subgraphs[index].id: index,
    });
    _buildMaps(graph.nodes, graph.edges);
    final mainInstructionStart = _instructions.length;
    _compileFromEntry(entryNodeId ?? graph.entryNodeId);
    if (graph.nodes.isNotEmpty &&
        _instructions.length == mainInstructionStart) {
      throw StateError(
        'Graph entry node does not resolve to executable nodes.',
      );
    }
    _emit(const DartGraphInstruction(op: DartGraphOpCode.halt));

    final compiledSubgraphs = <DartCompiledSubgraphV2>[];
    for (final subgraph in subgraphs) {
      compiledSubgraphs.add(_compileSubgraph(subgraph));
    }
    _resolveLabels();

    final slotNames = List<String>.filled(_nextSlot, '');
    for (final entry in _slotAliases.entries) {
      final current = slotNames[entry.value];
      if (current.isEmpty || current.contains(':')) {
        slotNames[entry.value] = entry.key;
      }
    }
    for (final entry in _localSlots.entries) {
      final current = slotNames[entry.value];
      if (current.isEmpty || current.contains(':')) {
        slotNames[entry.value] = entry.key;
      }
    }

    final allWires = <DataWire>[
      ...dataWires,
      for (final subgraph in subgraphs) ...subgraph.dataWires,
    ];
    final wireMap = <String, DartGraphWireSource>{};
    for (final wire in allWires) {
      wireMap['${wire.toNode}:${wire.toPort}'] = DartGraphWireSource(
        fromNodeId: wire.fromNode,
        fromPort: wire.fromPort,
      );
    }
    final wireTargetNodeIds = <String>{
      ..._contextSourceNodeIds,
      ...graph.nodes.map((node) => node.id),
      for (final subgraph in subgraphs)
        ...subgraph.nodes.map((node) => node.id),
    };
    return DartGraphProgram(
      instructions: List.unmodifiable(_instructions),
      actionNodes: List.unmodifiable(_actionNodes),
      subgraphs: List.unmodifiable(compiledSubgraphs),
      localSlotCount: _nextSlot,
      slotNames: List.unmodifiable(slotNames),
      wireMap: Map.unmodifiable(wireMap),
      contextSourceNodeIds: List.unmodifiable(_contextSourceNodeIds),
      wireTargetNodeIds: List.unmodifiable(wireTargetNodeIds),
      dataWires: List.unmodifiable(dataWires),
      outputs: const [],
      loopLimits: Map.unmodifiable(_loopLimits),
      loopNodeIds: Set.unmodifiable(_loopNodeIds),
    );
  }

  void _reset() {
    _instructions.clear();
    _actionNodes.clear();
    _localSlots.clear();
    _slotAliases.clear();
    _edgeMap.clear();
    _nodeMap.clear();
    _subgraphIndexById.clear();
    _contextSourceNodeIds
      ..clear()
      ..add('trigger');
    _nodePc.clear();
    _loopRepeatLabels.clear();
    _loopLimits.clear();
    _loopNodeIds.clear();
    _loopExitStack.clear();
    _loopHeaderStack.clear();
    _loopContinueStack.clear();
    _labels.clear();
    _pendingJumps.clear();
    _nextSlot = 0;
    _nextLabel = 0;
  }

  void _buildMaps(List<GraphNode> nodes, List<GraphEdge> edges) {
    for (final node in nodes) {
      _nodeMap[node.id] = node;
    }
    for (final edge in edges) {
      if (!_nodeMap.containsKey(edge.to) &&
          !_contextSourceNodeIds.contains(edge.to)) {
        throw StateError('Edge ${edge.id} references unknown node ${edge.to}.');
      }
      _edgeMap.putIfAbsent(edge.from, () => []).add(edge);
    }
  }

  void _compileFromEntry(String entryNodeId) {
    final visited = <String>{};
    if (_contextSourceNodeIds.contains(entryNodeId)) {
      for (final target in _getEdgeTargets(entryNodeId, null)) {
        _compileNode(target, visited);
      }
    } else {
      _compileNode(entryNodeId, visited);
    }
  }

  void _compileNode(String nodeId, Set<String> visited) {
    if (visited.contains(nodeId)) {
      final repeatLabel = _loopRepeatLabels[nodeId];
      if (repeatLabel != null) {
        _emitJumpToLabel(DartGraphOpCode.jump, repeatLabel, nodeId);
        return;
      }
      final pc = _nodePc[nodeId];
      if (pc != null) {
        _instructions.add(
          DartGraphInstruction(
            op: DartGraphOpCode.jump,
            nodeId: nodeId,
            arg0: pc,
          ),
        );
      }
      return;
    }
    visited.add(nodeId);
    final node = _nodeMap[nodeId];
    if (node == null) return;
    _nodePc[nodeId] = _instructions.length;
    switch (node.type) {
      case 'action' || 'queue.addItem' || 'overlay.pushChat':
        _compileAction(node, visited);
      case 'if':
        _compileIf(node, visited);
      case 'switch':
        _compileSwitch(node, visited);
      case 'for':
        _compileFor(node, visited);
      case 'forEach':
        _compileForEach(node, visited);
      case 'while':
        _compileWhile(node, visited);
      case 'break':
        _compileBreak(node);
      case 'continue':
        _compileContinue(node);
      case 'return':
        _compileReturn(node);
      case 'subgraph' || 'subgraphCall' || 'call':
        _compileSubgraphCall(node, visited);
      default:
        _compileDefault(node, visited);
    }
  }

  void _compileAction(GraphNode node, Set<String> visited) {
    final index = _actionNodes.length;
    _actionNodes.add(_compatibilityActionNode(node));
    _emit(
      DartGraphInstruction(
        op: DartGraphOpCode.exec,
        nodeId: node.id,
        arg0: index,
      ),
    );
    final next = _getDefaultEdgeTarget(node.id);
    if (next != null) _compileNode(next, visited);
  }

  void _compileIf(GraphNode node, Set<String> visited) {
    final elseLabel = _newLabel();
    final endLabel = _newLabel();
    _emit(
      DartGraphInstruction(
        op: DartGraphOpCode.eval,
        nodeId: node.id,
        arg1: node.data['condition'],
      ),
    );
    _emitJumpToLabel(DartGraphOpCode.jumpIfNot, elseLabel, node.id);
    final thenTarget = _getEdgeTarget(node.id, 'then');
    if (thenTarget != null) _compileNode(thenTarget, visited);
    _emitJumpToLabel(DartGraphOpCode.jump, endLabel, node.id);
    _placeLabel(elseLabel);
    final elseTarget = _getEdgeTarget(node.id, 'else');
    if (elseTarget != null) _compileNode(elseTarget, visited);
    _placeLabel(endLabel);
    final next = _getEdgeTarget(node.id, 'next');
    if (next != null) _compileNode(next, visited);
  }

  void _compileSwitch(GraphNode node, Set<String> visited) {
    final endLabel = _newLabel();
    final switchSlot = _allocSlot('${node.id}:switchVal');
    _emit(
      DartGraphInstruction(
        op: DartGraphOpCode.eval,
        nodeId: node.id,
        arg1: node.data['expression'],
      ),
    );
    _emit(
      DartGraphInstruction(
        op: DartGraphOpCode.store,
        nodeId: node.id,
        arg0: switchSlot,
      ),
    );
    final switchName = '__switch_${node.id}';
    _bindSlot(switchName, switchSlot);
    final cases = node.data['cases'];
    if (cases is List) {
      for (final item in cases.whereType<Map>()) {
        final skipLabel = _newLabel();
        _emit(
          DartGraphInstruction(
            op: DartGraphOpCode.eval,
            nodeId: node.id,
            arg1: {
              'type': 'binary',
              'op': '==',
              'left': {'type': 'variable', 'name': switchName},
              'right': {'type': 'literal', 'value': item['value']},
            },
          ),
        );
        _emitJumpToLabel(DartGraphOpCode.jumpIfNot, skipLabel, node.id);
        final target = _getEdgeTarget(node.id, item['port']?.toString());
        if (target != null) _compileNode(target, visited);
        _emitJumpToLabel(DartGraphOpCode.jump, endLabel, node.id);
        _placeLabel(skipLabel);
      }
    }
    final defaultTarget = _getEdgeTarget(node.id, 'default');
    if (defaultTarget != null) _compileNode(defaultTarget, visited);
    _placeLabel(endLabel);
    final next = _getEdgeTarget(node.id, 'next');
    if (next != null) _compileNode(next, visited);
  }

  void _compileFor(GraphNode node, Set<String> visited) {
    _loopNodeIds.add(node.id);
    final counterSlot = _allocSlot('${node.id}:counter');
    final endSlot = _allocSlot('${node.id}:end');
    final headerLabel = _newLabel();
    final exitLabel = _newLabel();
    final continueLabel = _newLabel();
    _emit(
      DartGraphInstruction(
        op: DartGraphOpCode.eval,
        nodeId: node.id,
        arg1: node.data['start'],
      ),
    );
    _emit(
      DartGraphInstruction(
        op: DartGraphOpCode.store,
        nodeId: node.id,
        arg0: counterSlot,
      ),
    );
    _emit(
      DartGraphInstruction(
        op: DartGraphOpCode.eval,
        nodeId: node.id,
        arg1: node.data['end'],
      ),
    );
    _emit(
      DartGraphInstruction(
        op: DartGraphOpCode.store,
        nodeId: node.id,
        arg0: endSlot,
      ),
    );
    final variable = node.data['variable']?.toString() ?? 'index';
    _bindSlot(variable, counterSlot);
    _loopRepeatLabels[node.id] = continueLabel;
    _placeLabel(headerLabel);
    final checkIndex = _instructions.length;
    _emit(
      DartGraphInstruction(
        op: DartGraphOpCode.loopCheck,
        nodeId: node.id,
        arg0: counterSlot,
        arg1: endSlot,
        arg2: -1,
      ),
    );
    _pendingJumps.add((instructionIndex: checkIndex, labelId: exitLabel));
    _loopExitStack.add(exitLabel);
    _loopHeaderStack.add(headerLabel);
    _loopContinueStack.add(continueLabel);
    final body = _getEdgeTarget(node.id, 'body');
    if (body != null) _compileNode(body, visited);
    _placeLabel(continueLabel);
    _emit(
      DartGraphInstruction(op: DartGraphOpCode.yieldControl, nodeId: node.id),
    );
    _emit(
      DartGraphInstruction(
        op: DartGraphOpCode.loopStep,
        nodeId: node.id,
        arg0: counterSlot,
        arg1: node.data['step'],
      ),
    );
    _emitJumpToLabel(DartGraphOpCode.jump, headerLabel, node.id);
    _placeLabel(exitLabel);
    _loopHeaderStack.removeLast();
    _loopExitStack.removeLast();
    _loopContinueStack.removeLast();
    _loopRepeatLabels.remove(node.id);
    final next = _getEdgeTarget(node.id, 'next');
    if (next != null) _compileNode(next, visited);
  }

  void _compileForEach(GraphNode node, Set<String> visited) {
    _loopNodeIds.add(node.id);
    final itemSlot = _allocSlot('${node.id}:item');
    final indexSlot = _allocSlot('${node.id}:index');
    final collSlot = _allocSlot('${node.id}:coll');
    final headerLabel = _newLabel();
    final exitLabel = _newLabel();
    final continueLabel = _newLabel();
    _emit(
      DartGraphInstruction(
        op: DartGraphOpCode.eval,
        nodeId: node.id,
        arg1: node.data['collection'],
      ),
    );
    _emit(
      DartGraphInstruction(
        op: DartGraphOpCode.store,
        nodeId: node.id,
        arg0: collSlot,
      ),
    );
    _emit(
      DartGraphInstruction(
        op: DartGraphOpCode.eval,
        nodeId: node.id,
        arg1: const {'type': 'literal', 'value': 0},
      ),
    );
    _emit(
      DartGraphInstruction(
        op: DartGraphOpCode.store,
        nodeId: node.id,
        arg0: indexSlot,
      ),
    );
    _bindSlot(node.data['variable']?.toString() ?? 'item', itemSlot);
    final indexVariable = node.data['indexVariable']?.toString();
    if (indexVariable != null && indexVariable.isNotEmpty) {
      _bindSlot(indexVariable, indexSlot);
    }
    _loopRepeatLabels[node.id] = continueLabel;
    _placeLabel(headerLabel);
    final iterIndex = _instructions.length;
    _emit(
      DartGraphInstruction(
        op: DartGraphOpCode.iterNext,
        nodeId: node.id,
        arg0: itemSlot,
        arg1: DartGraphIterNextArgs(
          itemSlot: itemSlot,
          indexSlot: indexSlot,
          collSlot: collSlot,
        ),
        arg2: -1,
      ),
    );
    _pendingJumps.add((instructionIndex: iterIndex, labelId: exitLabel));
    _loopExitStack.add(exitLabel);
    _loopHeaderStack.add(headerLabel);
    _loopContinueStack.add(continueLabel);
    final body = _getEdgeTarget(node.id, 'body');
    if (body != null) _compileNode(body, visited);
    _placeLabel(continueLabel);
    _emit(
      DartGraphInstruction(op: DartGraphOpCode.yieldControl, nodeId: node.id),
    );
    _emit(
      DartGraphInstruction(
        op: DartGraphOpCode.loopStep,
        nodeId: node.id,
        arg0: indexSlot,
        arg1: const {'type': 'literal', 'value': 1},
      ),
    );
    _emitJumpToLabel(DartGraphOpCode.jump, headerLabel, node.id);
    _placeLabel(exitLabel);
    _loopHeaderStack.removeLast();
    _loopExitStack.removeLast();
    _loopContinueStack.removeLast();
    _loopRepeatLabels.remove(node.id);
    final next = _getEdgeTarget(node.id, 'next');
    if (next != null) _compileNode(next, visited);
  }

  void _compileWhile(GraphNode node, Set<String> visited) {
    _loopNodeIds.add(node.id);
    final maxIterations = node.data['maxIterations'];
    if (maxIterations is num && maxIterations > 0) {
      _loopLimits[node.id] = maxIterations.toInt();
    }
    final headerLabel = _newLabel();
    final exitLabel = _newLabel();
    _placeLabel(headerLabel);
    _emit(
      DartGraphInstruction(
        op: DartGraphOpCode.eval,
        nodeId: node.id,
        arg1: node.data['condition'],
      ),
    );
    _emitJumpToLabel(DartGraphOpCode.jumpIfNot, exitLabel, node.id);
    _loopExitStack.add(exitLabel);
    _loopHeaderStack.add(headerLabel);
    _loopContinueStack.add(headerLabel);
    final body = _getEdgeTarget(node.id, 'body');
    if (body != null) _compileNode(body, visited);
    _emit(
      DartGraphInstruction(op: DartGraphOpCode.yieldControl, nodeId: node.id),
    );
    _emitJumpToLabel(DartGraphOpCode.jump, headerLabel, node.id);
    _placeLabel(exitLabel);
    _loopHeaderStack.removeLast();
    _loopExitStack.removeLast();
    _loopContinueStack.removeLast();
    final next = _getEdgeTarget(node.id, 'next');
    if (next != null) _compileNode(next, visited);
  }

  void _compileBreak(GraphNode node) {
    if (_loopExitStack.isNotEmpty) {
      _emitJumpToLabel(DartGraphOpCode.jump, _loopExitStack.last, node.id);
    }
  }

  void _compileContinue(GraphNode node) {
    if (_loopContinueStack.isNotEmpty) {
      _emitJumpToLabel(DartGraphOpCode.jump, _loopContinueStack.last, node.id);
    }
  }

  void _compileReturn(GraphNode node) => _emit(
    DartGraphInstruction(
      op: DartGraphOpCode.ret,
      nodeId: node.id,
      arg1: node.data['outputs'],
    ),
  );

  void _compileSubgraphCall(GraphNode node, Set<String> visited) {
    final id = node.data['subgraphId']?.toString();
    final index = id == null ? null : _subgraphIndexById[id];
    if (index == null) throw StateError('Subgraph not found: $id');
    _emit(
      DartGraphInstruction(
        op: DartGraphOpCode.call,
        nodeId: node.id,
        arg0: index,
        arg1: node.data['inputs'],
      ),
    );
    final next = _getDefaultEdgeTarget(node.id);
    if (next != null) _compileNode(next, visited);
  }

  void _compileDefault(GraphNode node, Set<String> visited) {
    final next = _getDefaultEdgeTarget(node.id);
    if (next != null) _compileNode(next, visited);
  }

  DartCompiledSubgraphV2 _compileSubgraph(SubgraphDefinition subgraph) {
    final entryPc = _instructions.length;
    final previousLocalSlots = Map<String, int>.from(_localSlots);
    final subgraphSlotStart = _nextSlot;
    final previousEdges = Map<String, List<GraphEdge>>.from(_edgeMap);
    final previousNodes = Map<String, GraphNode>.from(_nodeMap);
    final previousNodePc = Map<String, int>.from(_nodePc);
    final previousLoopRepeatLabels = Map<String, int>.from(_loopRepeatLabels);
    _edgeMap.clear();
    _nodeMap.clear();
    _nodePc.clear();
    _loopRepeatLabels.clear();
    _buildMaps(subgraph.nodes, subgraph.edges);
    final paramSlots = <int>[];
    for (final parameter in subgraph.parameters) {
      final name = parameter['name']?.toString() ?? '';
      final slot = _allocSlot('sg:${subgraph.id}:$name');
      paramSlots.add(slot);
      if (name.isNotEmpty) _bindSlot(name, slot);
    }
    final subgraphInstructionStart = _instructions.length;
    _compileFromEntry(subgraph.entryNodeId);
    if (subgraph.nodes.isNotEmpty &&
        _instructions.length == subgraphInstructionStart) {
      throw StateError('Subgraph entry node does not resolve: ${subgraph.id}.');
    }
    final outputs = <String, dynamic>{};
    for (final output in subgraph.outputs) {
      final name = output['name']?.toString();
      if (name != null && name.isNotEmpty && output['expression'] != null) {
        outputs[name] = output['expression'];
      }
    }
    _emit(
      DartGraphInstruction(
        op: DartGraphOpCode.ret,
        arg1: outputs.isEmpty ? null : outputs,
      ),
    );
    final localSlotsByName = <String, int>{
      for (final entry in _localSlots.entries)
        if (entry.value >= subgraphSlotStart ||
            previousLocalSlots[entry.key] != entry.value)
          entry.key: entry.value,
    };
    _edgeMap
      ..clear()
      ..addAll(previousEdges);
    _nodeMap
      ..clear()
      ..addAll(previousNodes);
    _nodePc
      ..clear()
      ..addAll(previousNodePc);
    _loopRepeatLabels
      ..clear()
      ..addAll(previousLoopRepeatLabels);
    return DartCompiledSubgraphV2(
      id: subgraph.id,
      name: subgraph.name,
      entryPc: entryPc,
      paramSlots: List.unmodifiable(paramSlots),
      paramNames: List.unmodifiable(
        subgraph.parameters
            .map((parameter) => parameter['name']?.toString() ?? '')
            .toList(),
      ),
      localSlotsByName: Map.unmodifiable(localSlotsByName),
    );
  }

  int _allocSlot(String key) {
    final existing = _localSlots[key];
    if (existing != null) return existing;
    final slot = _nextSlot++;
    _localSlots[key] = slot;
    _slotAliases[key] = slot;
    return slot;
  }

  void _bindSlot(String name, int slot) {
    _localSlots[name] = slot;
    _slotAliases[name] = slot;
  }

  String? _getEdgeTarget(String nodeId, String? port) =>
      _getEdgeTargets(nodeId, port).firstOrNull;

  List<String> _getEdgeTargets(String nodeId, String? port) =>
      (_edgeMap[nodeId] ?? const <GraphEdge>[])
          .where((edge) => edge.port == port)
          .map((edge) => edge.to)
          .toList();

  String? _getDefaultEdgeTarget(String nodeId) {
    final direct = _getEdgeTarget(nodeId, null);
    if (direct != null) return direct;
    return _getEdgeTarget(nodeId, 'completed') ??
        _getEdgeTarget(nodeId, 'out') ??
        (_edgeMap[nodeId] ?? const <GraphEdge>[]).firstOrNull?.to;
  }

  void _emit(DartGraphInstruction instruction) =>
      _instructions.add(instruction);

  int _newLabel() => _nextLabel++;

  void _placeLabel(int label) => _labels[label] = _instructions.length;

  void _emitJumpToLabel(DartGraphOpCode op, int label, String? nodeId) {
    final index = _instructions.length;
    _emit(DartGraphInstruction(op: op, nodeId: nodeId, arg0: -1));
    _pendingJumps.add((instructionIndex: index, labelId: label));
  }

  void _resolveLabels() {
    for (final pending in _pendingJumps) {
      final target = _labels[pending.labelId];
      if (target == null) continue;
      final old = _instructions[pending.instructionIndex];
      final isExitJump =
          old.op == DartGraphOpCode.loopCheck ||
          old.op == DartGraphOpCode.iterNext;
      _instructions[pending.instructionIndex] = DartGraphInstruction(
        op: old.op,
        nodeId: old.nodeId,
        arg0: isExitJump ? old.arg0 : target,
        arg1: old.arg1,
        arg2: isExitJump ? target : old.arg2,
      );
    }
  }
}

final class DartGraphVm {
  DartGraphVm(
    this.program, {
    this.maxIterations = 10000,
    this.maxCallDepth = 32,
    this.onStep,
    this.onNodeEnter,
    this.onNodeExit,
  });

  final DartGraphProgram program;
  final int maxIterations;
  final int maxCallDepth;
  final DartProgramStep? onStep;
  final void Function(String nodeId)? onNodeEnter;
  final void Function(String nodeId)? onNodeExit;

  int _pc = 0;
  List<dynamic> _locals = [];
  final List<dynamic> _stack = [];
  final List<_DartGraphCallFrame> _callStack = [];
  final Map<String, int> _iterationCounters = {};
  final Map<String, RuntimeMap> _nodeResults = {};
  final Map<String, int> _localSlotsByName = {};
  late EvaluationContext _context;
  late Map<String, List<({String toPort, DartGraphWireSource source})>>
  _nodeWireInputs;
  bool _didReturn = false;
  Map<String, dynamic> _outputValues = {};
  String? _activeNodeId;

  Future<GraphExecutionResult> execute({
    required EvaluationContext context,
    required DartProgramAction action,
  }) async {
    _locals = List<dynamic>.filled(program.localSlotCount, null);
    _stack.clear();
    _callStack.clear();
    _iterationCounters.clear();
    _nodeResults.clear();
    _didReturn = false;
    _outputValues = {};
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
        if (nodeId != null && nodeId != _activeNodeId) {
          if (_activeNodeId != null) onNodeExit?.call(_activeNodeId!);
          _activeNodeId = nodeId;
          onNodeEnter?.call(nodeId);
        }
        onStep?.call(instruction, _callStack.length);
        final advance = await _step(instruction, action);
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
    _syncLocalsToContext();
    _context.cancellationToken?.throwIfCancelled();
    final result = await action(node, _resolveActionConfig(node), _context);
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
    _callStack.add(
      _DartGraphCallFrame(
        returnPc: _pc + 1,
        localSnapshot: List<dynamic>.of(_locals),
        callNodeId: callNodeId,
        localSlotsByName: Map<String, int>.from(_localSlotsByName),
        contextLocals: Map<String, dynamic>.from(_context.locals),
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
    _locals = frame.localSnapshot;
    _localSlotsByName
      ..clear()
      ..addAll(frame.localSlotsByName);
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
  });

  final int returnPc;
  final List<dynamic> localSnapshot;
  final String? callNodeId;
  final Map<String, int> localSlotsByName;
  final Map<String, dynamic> contextLocals;
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

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
