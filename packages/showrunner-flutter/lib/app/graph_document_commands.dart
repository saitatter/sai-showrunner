part of '../main.dart';

extension _GraphDocumentCommands on _ShowRunnerPageState {
  Future<void> _copyGraph({bool cut = false}) async {
    final graph = _graphEditor.graph;
    final selection = graph.selection;
    final revision = graph.revision;
    final spaceId = graph.activeSpaceId;
    final fragment = GraphFragment.capture(graph);
    await Clipboard.setData(ClipboardData(text: fragment.encode()));
    if (cut &&
        mounted &&
        identical(graph, _graphEditor.graph) &&
        revision == graph.revision &&
        spaceId == graph.activeSpaceId) {
      graph.deleteSelection(selected: selection);
    }
  }

  Future<void> _pasteGraph() async {
    final graph = _graphEditor.graph;
    final data = await Clipboard.getData('text/plain');
    if (!mounted ||
        !identical(graph, _graphEditor.graph) ||
        data?.text == null) {
      return;
    }
    try {
      graph.pasteGraphFragment(GraphFragment.decode(data!.text!));
    } catch (error) {
      if (mounted) {
        showShowRunnerFeedback(
          context,
          'Cannot paste nodes: $error',
          severity: ShowRunnerFeedbackSeverity.error,
        );
      }
    }
  }
}
