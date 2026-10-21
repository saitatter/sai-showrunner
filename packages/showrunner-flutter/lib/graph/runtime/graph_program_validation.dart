import 'graph_program.dart';

/// Validates operand addresses before a VM can invoke an action callback.
/// Stack values remain dynamic; runtime guards enforce execution limits.
void validateGraphProgram(DartGraphProgram program) {
  Never invalid(String detail) =>
      throw StateError('Invalid graph program: $detail');
  void index(Object? value, int length, String label, {bool allowEnd = false}) {
    if (value is! int || value < 0 || value >= length + (allowEnd ? 1 : 0)) {
      invalid('$label is outside its address space.');
    }
  }

  void slot(Object? value) => index(value, program.localSlotCount, 'slot');
  void pc(Object? value) =>
      index(value, program.instructions.length, 'jump target', allowEnd: true);
  if (program.localSlotCount < 0 ||
      program.slotNames.length != program.localSlotCount) {
    invalid('slot names/count disagree.');
  }
  for (final subgraph in program.subgraphs) {
    index(subgraph.entryPc, program.instructions.length, 'subgraph entry');
    if (subgraph.paramNames.length != subgraph.paramSlots.length) {
      invalid('subgraph parameter names/slots disagree.');
    }
    for (final value in [
      ...subgraph.paramSlots,
      ...subgraph.localSlotsByName.values,
    ]) {
      slot(value);
    }
  }
  for (final instruction in program.instructions) {
    if (instruction.arg1 case RuntimeSlotReference(:final slot)) {
      index(slot, program.localSlotCount, 'input slot');
    }
    switch (instruction.op) {
      case DartGraphOpCode.exec:
        index(instruction.arg0, program.actionNodes.length, 'action');
      case DartGraphOpCode.call:
        index(instruction.arg0, program.subgraphs.length, 'subgraph');
      case DartGraphOpCode.jump ||
          DartGraphOpCode.jumpIf ||
          DartGraphOpCode.jumpIfNot:
        pc(instruction.arg0);
      case DartGraphOpCode.store ||
          DartGraphOpCode.load ||
          DartGraphOpCode.loopStep:
        slot(instruction.arg0);
      case DartGraphOpCode.loopCheck:
        slot(instruction.arg0);
        if (instruction.arg1 case DartGraphLoopCheckArgs(
          :final endSlot,
          :final stepSlot,
        )) {
          slot(endSlot);
          slot(stepSlot);
        } else {
          invalid('loop operands are missing.');
        }
        pc(instruction.arg2);
      case DartGraphOpCode.iterNext:
        if (instruction.arg1 case DartGraphIterNextArgs(
          :final itemSlot,
          :final indexSlot,
          :final collSlot,
        )) {
          slot(itemSlot);
          slot(indexSlot);
          slot(collSlot);
        } else {
          invalid('iterator operands are missing.');
        }
        pc(instruction.arg2);
      case DartGraphOpCode.eval ||
          DartGraphOpCode.loopInit ||
          DartGraphOpCode.iterInit ||
          DartGraphOpCode.ret ||
          DartGraphOpCode.yieldControl ||
          DartGraphOpCode.halt:
        break;
    }
  }
}
