import 'dart:async';

import '../schema/automation.dart';
import 'expression.dart';

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
    this.edgeId,
    this.edgeFromNodeId,
    this.edgeToNodeId,
    this.edgePort,
  });

  final DartGraphOpCode op;
  final String? nodeId;
  final int? arg0;
  final Object? arg1;
  final Object? arg2;
  final String? edgeId;
  final String? edgeFromNodeId;
  final String? edgeToNodeId;
  final String? edgePort;
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
    required this.nodeTypes,
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
  final Map<String, String> nodeTypes;
}

typedef DartProgramAction =
    Future<Object?> Function(
      GraphNode node,
      RuntimeMap config,
      EvaluationContext context,
    );

typedef DartProgramStep =
    void Function(DartGraphInstruction instruction, int depth);
