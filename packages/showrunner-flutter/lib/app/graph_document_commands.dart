part of 'showrunner_page.dart';

extension _GraphDocumentCommands on _ShowRunnerPageState {
  Future<void> _copyGraph({bool cut = false}) async {
    final graph = _graphEditor.graph;
    final selection = graph.selection;
    final revision = graph.revision;
    final spaceId = graph.activeSpaceId;
    final fragment = _graphEditor.captureFragment();
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
    final spaceId = graph.activeSpaceId;
    try {
      final data = await Clipboard.getData('text/plain');
      if (!mounted ||
          !identical(graph, _graphEditor.graph) ||
          graph.activeSpaceId != spaceId ||
          data?.text == null) {
        return;
      }
      _graphEditor.pasteFragment(GraphFragment.decode(data!.text!));
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
