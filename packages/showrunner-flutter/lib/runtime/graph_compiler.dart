import '../schema/automation.dart';

import 'graph_program.dart';

final class DartProductionGraphCompiler {
  DartProductionGraphCompiler({this.yieldInterval = 64});

  final int yieldInterval;
  final List<DartGraphInstruction> _instructions = [];
  final List<GraphNode> _actionNodes = [];
  final Map<String, int> _localSlots = {};
  final Map<String, int> _slotAliases = {};
  final Map<String, List<GraphEdge>> _edgeMap = {};
  final Map<String, GraphNode> _nodeMap = {};
  final Map<String, String> _nodeTypes = {};
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
      nodeTypes: Map.unmodifiable(_nodeTypes),
    );
  }

  void _reset() {
    _instructions.clear();
    _actionNodes.clear();
    _localSlots.clear();
    _slotAliases.clear();
    _edgeMap.clear();
    _nodeMap.clear();
    _nodeTypes.clear();
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
      _nodeTypes[node.id] = node.type;
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
      for (final edge in _getEdges(entryNodeId, null)) {
        _compileEdge(edge, visited);
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
      case 'action':
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
    _actionNodes.add(node);
    _emit(
      DartGraphInstruction(
        op: DartGraphOpCode.exec,
        nodeId: node.id,
        arg0: index,
      ),
    );
    final next = _getDefaultEdge(node.id);
    if (next != null) _compileEdge(next, visited);
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
    final thenTarget = _getEdge(node.id, 'then');
    if (thenTarget != null) _compileEdge(thenTarget, visited);
    _emitJumpToLabel(DartGraphOpCode.jump, endLabel, node.id);
    _placeLabel(elseLabel);
    final elseTarget = _getEdge(node.id, 'else');
    if (elseTarget != null) _compileEdge(elseTarget, visited);
    _placeLabel(endLabel);
    final next = _getEdge(node.id, 'next');
    if (next != null) _compileEdge(next, visited);
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
        final target = _getEdge(node.id, item['port']?.toString());
        if (target != null) _compileEdge(target, visited);
        _emitJumpToLabel(DartGraphOpCode.jump, endLabel, node.id);
        _placeLabel(skipLabel);
      }
    }
    final defaultTarget = _getEdge(node.id, 'default');
    if (defaultTarget != null) _compileEdge(defaultTarget, visited);
    _placeLabel(endLabel);
    final next = _getEdge(node.id, 'next');
    if (next != null) _compileEdge(next, visited);
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
    final body = _getEdge(node.id, 'body');
    if (body != null) _compileEdge(body, visited);
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
    final next = _getEdge(node.id, 'next');
    if (next != null) _compileEdge(next, visited);
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
    final body = _getEdge(node.id, 'body');
    if (body != null) _compileEdge(body, visited);
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
    final next = _getEdge(node.id, 'next');
    if (next != null) _compileEdge(next, visited);
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
    final body = _getEdge(node.id, 'body');
    if (body != null) _compileEdge(body, visited);
    _emit(
      DartGraphInstruction(op: DartGraphOpCode.yieldControl, nodeId: node.id),
    );
    _emitJumpToLabel(DartGraphOpCode.jump, headerLabel, node.id);
    _placeLabel(exitLabel);
    _loopHeaderStack.removeLast();
    _loopExitStack.removeLast();
    _loopContinueStack.removeLast();
    final next = _getEdge(node.id, 'next');
    if (next != null) _compileEdge(next, visited);
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
    final next = _getDefaultEdge(node.id);
    if (next != null) _compileEdge(next, visited);
  }

  void _compileDefault(GraphNode node, Set<String> visited) {
    final next = _getDefaultEdge(node.id);
    if (next != null) _compileEdge(next, visited);
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

  GraphEdge? _getEdge(String nodeId, String? port) =>
      (_edgeMap[nodeId] ?? const <GraphEdge>[])
          .where((edge) => edge.port == port)
          .firstOrNull;

  List<GraphEdge> _getEdges(String nodeId, String? port) =>
      (_edgeMap[nodeId] ?? const <GraphEdge>[])
          .where((edge) => edge.port == port)
          .toList();

  GraphEdge? _getDefaultEdge(String nodeId) {
    final direct = _getEdge(nodeId, null);
    if (direct != null) return direct;
    return _getEdge(nodeId, 'completed') ??
        _getEdge(nodeId, 'out') ??
        (_edgeMap[nodeId] ?? const <GraphEdge>[]).firstOrNull;
  }

  void _compileEdge(GraphEdge edge, Set<String> visited) {
    final firstInstruction = _instructions.length;
    _compileNode(edge.to, visited);
    if (_instructions.length <= firstInstruction) return;
    final old = _instructions[firstInstruction];
    _instructions[firstInstruction] = DartGraphInstruction(
      op: old.op,
      nodeId: old.nodeId,
      arg0: old.arg0,
      arg1: old.arg1,
      arg2: old.arg2,
      edgeId: edge.id,
      edgeFromNodeId: edge.from,
      edgeToNodeId: edge.to,
      edgePort: edge.port,
    );
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
        edgeId: old.edgeId,
        edgeFromNodeId: old.edgeFromNodeId,
        edgeToNodeId: old.edgeToNodeId,
        edgePort: old.edgePort,
      );
    }
  }
}
