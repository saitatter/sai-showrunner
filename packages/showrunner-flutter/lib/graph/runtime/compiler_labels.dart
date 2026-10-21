import 'graph_program.dart';

/// Label placement and relocation preserve instruction and edge identity.
final class CompilerLabels {
  final Map<int, int> _labels = {};
  final List<({int instructionIndex, int labelId})> _pendingJumps = [];
  int _nextLabel = 0;

  int allocate() => _nextLabel++;
  void place(int label, int pc) => _labels[label] = pc;
  void reference(int instructionIndex, int labelId) =>
      _pendingJumps.add((instructionIndex: instructionIndex, labelId: labelId));
  void reset() {
    _labels.clear();
    _pendingJumps.clear();
    _nextLabel = 0;
  }

  void resolve(List<DartGraphInstruction> instructions) {
    for (final pending in _pendingJumps) {
      final target = _labels[pending.labelId];
      if (target == null) {
        throw StateError('Unresolved compiler label ${pending.labelId}.');
      }
      final old = instructions[pending.instructionIndex];
      final isExitJump =
          old.op == DartGraphOpCode.loopCheck ||
          old.op == DartGraphOpCode.iterNext;
      instructions[pending.instructionIndex] = DartGraphInstruction(
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
