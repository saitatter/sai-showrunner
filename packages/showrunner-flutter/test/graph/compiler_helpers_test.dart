import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/graph/runtime/compiler_labels.dart';
import 'package:showrunner_flutter/graph/runtime/compiler_slots.dart';
import 'package:showrunner_flutter/graph/runtime/graph_compiler.dart';
import 'package:showrunner_flutter/graph/runtime/graph_program.dart';
import 'package:showrunner_flutter/graph/runtime/graph_program_validation.dart';
import 'package:showrunner_flutter/graph/runtime/graph_vm.dart';
import 'package:showrunner_flutter/graph/runtime/vm_value_operations.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import '../support/graph_fixtures.dart';

void main() {
  test(
    'labels relocate branches and loop exits without losing correlation',
    () {
      final labels = CompilerLabels();
      final end = labels.allocate();
      final instructions = [
        for (final op in [
          DartGraphOpCode.jump,
          DartGraphOpCode.loopCheck,
          DartGraphOpCode.iterNext,
        ])
          DartGraphInstruction(
            op: op,
            arg0: -1,
            arg1: 'unchanged',
            arg2: -1,
            nodeId: 'node',
            edgeId: 'edge',
            edgeFromNodeId: 'from',
            edgeToNodeId: 'to',
            edgePort: 'flow:body',
          ),
        const DartGraphInstruction(op: DartGraphOpCode.halt),
      ];
      for (var pc = 0; pc < 3; pc++) {
        labels.reference(pc, end);
      }
      labels.place(end, 3);
      labels.resolve(instructions);
      expect(instructions.first.arg0, 3);
      for (final instruction in instructions.take(3)) {
        expect(instruction.arg1, 'unchanged');
        expect(instruction.nodeId, 'node');
        expect(instruction.edgeId, 'edge');
        expect(instruction.edgeFromNodeId, 'from');
        expect(instruction.edgeToNodeId, 'to');
        expect(instruction.edgePort, 'flow:body');
      }
      expect(instructions[1].arg0, -1);
      expect(instructions[1].arg2, 3);
      expect(instructions[2].arg2, 3);
      labels.reset();
      expect(labels.allocate(), 0);
    },
  );
  test('unplaced labels fail visibly instead of leaving invalid jumps', () {
    final labels = CompilerLabels();
    labels.reference(0, labels.allocate());
    expect(
      () => labels.resolve([
        const DartGraphInstruction(op: DartGraphOpCode.jump, arg0: -1),
      ]),
      throwsStateError,
    );
  });
  test(
    'slot allocation is deterministic and public aliases win generated names',
    () {
      final slots = CompilerSlots();
      final first = slots.allocate('sg:test:value');
      expect(slots.allocate('sg:test:value'), first);
      slots.bind('value', first);
      expect(slots.allocate('other'), 1);
      expect(slots.names, ['value', 'other']);
      slots.reset();
      expect(slots.count, 0);
      expect(slots.bindings, isEmpty);
      expect(slots.allocate('new'), 0);
    },
  );
  test('value cloning and nested writes do not mutate their input', () {
    final source = <String, dynamic>{
      'type': 'literal',
      'nested': {
        'value': [1, 2],
      },
    };
    final copy = vmCloneValue(source) as Map<String, dynamic>;
    vmSetPath(copy, 'nested.value', [3]);
    expect(vmGetPath(source, 'nested.value.0'), 1);
    expect(vmGetPath(copy, 'nested.value.0'), 3);
    expect(vmGetPath(copy, 'nested.value.-1'), isNull);
    expect(copy['type'], 'literal');
    expect(vmNormalizeActionResult(42), {'_result': 42});
    expect(vmNormalizeActionResult(null), isNull);
  });
  final valid = DartProductionGraphCompiler().compileAutomation(
    automationFixture(nodes: [actionFixture('a')], entryNodeId: 'a'),
  );
  test('compiler output passes the operand validator', () {
    expect(() => validateGraphProgram(valid), returnsNormally);
    expect(DartGraphOpCode.values, hasLength(16));
  });
  for (final instruction in [
    const DartGraphInstruction(op: DartGraphOpCode.exec, arg0: 99),
    const DartGraphInstruction(op: DartGraphOpCode.call, arg0: 0),
    const DartGraphInstruction(op: DartGraphOpCode.jump, arg0: -1),
    const DartGraphInstruction(op: DartGraphOpCode.jumpIf, arg0: 999),
    const DartGraphInstruction(op: DartGraphOpCode.store, arg0: 0),
    const DartGraphInstruction(
      op: DartGraphOpCode.eval,
      arg1: RuntimeSlotReference(3),
    ),
    const DartGraphInstruction(op: DartGraphOpCode.loopCheck, arg0: 0, arg2: 0),
    const DartGraphInstruction(op: DartGraphOpCode.iterNext, arg2: 0),
  ]) {
    test('invalid ${instruction.op.name} fails before any action', () async {
      final program = replaceInstructions(valid, [
        valid.instructions.first,
        instruction,
      ]);
      var called = false;
      await expectLater(
        DartGraphVm(program).execute(
          context: EvaluationContext(),
          action: (node, config, context) async {
            called = true;
            return null;
          },
        ),
        throwsStateError,
      );
      expect(called, false);
    });
  }
}

DartGraphProgram replaceInstructions(
  DartGraphProgram original,
  List<DartGraphInstruction> instructions,
) => DartGraphProgram(
  instructions: instructions,
  actionNodes: original.actionNodes,
  subgraphs: original.subgraphs,
  localSlotCount: original.localSlotCount,
  slotNames: original.slotNames,
  wireMap: original.wireMap,
  contextSourceNodeIds: original.contextSourceNodeIds,
  wireTargetNodeIds: original.wireTargetNodeIds,
  dataWires: original.dataWires,
  outputs: original.outputs,
  loopLimits: original.loopLimits,
  loopNodeIds: original.loopNodeIds,
  nodeTypes: original.nodeTypes,
  values: original.values,
  rootSpaceId: original.rootSpaceId,
);
