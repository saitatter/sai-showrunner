part of '../showrunner_graph_editor.dart';

/// Execution visuals and editor-only preview state.
///
/// Runtime execution is owned by the application runtime. This adapter only
/// projects runtime callbacks onto graph nodes and provides the non-executing
/// preview playhead used by the editor.
extension ShowRunnerGraphEditorExecutionState on ShowRunnerGraphEditor {
  void markSchemaNodeRunning(String schemaId) {
    final editorId = editorNodeIdForSchema(schemaId);
    setActiveSchemaNodeIds([schemaId]);
    if (editorId == null) return;
    executionStates.value = {
      ...executionStates.value,
      editorId: GraphNodeExecutionVisual(
        status: GraphNodeExecutionStatus.running,
        startedAt: DateTime.now(),
      ),
    };
  }

  void markSchemaNodeCompleted(String schemaId) {
    final editorId = editorNodeIdForSchema(schemaId);
    if (editorId == null) return;
    final previous = executionStates.value[editorId];
    executionStates.value = {
      ...executionStates.value,
      editorId: GraphNodeExecutionVisual(
        status: GraphNodeExecutionStatus.success,
        startedAt: previous?.startedAt ?? DateTime.now(),
        duration: previous == null
            ? null
            : DateTime.now().difference(previous.startedAt),
      ),
    };
    setActiveSchemaNodeIds(const []);
  }

  void markActiveSchemaNodeFailed(Object error) {
    final editorId = activeNodeIds.value.firstOrNull;
    if (editorId == null) return;
    final previous = executionStates.value[editorId];
    executionStates.value = {
      ...executionStates.value,
      editorId: GraphNodeExecutionVisual(
        status: GraphNodeExecutionStatus.error,
        startedAt: previous?.startedAt ?? DateTime.now(),
        duration: previous == null
            ? null
            : DateTime.now().difference(previous.startedAt),
        error: error.toString(),
      ),
    };
    activeNodeIds.value = const {};
  }

  void clearExecutionStates() {
    executionStates.value = const {};
    activeNodeIds.value = const {};
  }

  List<NodeDataModel> get _previewNodes =>
      controller.nodes.values.where((node) => !isTriggerNode(node.id)).toList()
        ..sort((a, b) {
          final x = a.offset.dx.compareTo(b.offset.dx);
          return x != 0 ? x : a.offset.dy.compareTo(b.offset.dy);
        });

  Duration previewDurationFor(String nodeId) {
    final data = _nodeDataByEditorId[nodeId];
    final config = data?['config'];
    if (config is Map) {
      for (final key in const [
        'duration',
        'durationSeconds',
        'delay',
        'seconds',
      ]) {
        final value = config[key];
        final seconds = value is num
            ? value.toDouble()
            : double.tryParse('$value');
        if (seconds != null && seconds.isFinite && seconds > 0) {
          return Duration(milliseconds: (seconds * 1000).round());
        }
      }
    }
    return const Duration(milliseconds: 900);
  }

  Duration get previewTotal => _previewNodes.fold(
    Duration.zero,
    (total, node) => total + previewDurationFor(node.id),
  );

  double get previewProgress {
    final total = previewTotal.inMicroseconds;
    if (total <= 0) return 0;
    return (previewElapsed.value.inMicroseconds / total).clamp(0, 1).toDouble();
  }

  String? get previewRouteLabel {
    final node = controller.nodes[previewNodeId.value];
    return node?.prototype.idName;
  }

  void togglePreview() {
    if (previewPlaying.value) {
      _stopPreview();
      return;
    }
    final total = previewTotal;
    if (total <= Duration.zero) return;
    if (previewElapsed.value >= total) previewElapsed.value = Duration.zero;
    previewPlaying.value = true;
    _previewStartedAt = DateTime.now().subtract(previewElapsed.value);
    _updatePreview();
    _previewTimer ??= Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _updatePreview(),
    );
  }

  void _updatePreview() {
    if (!previewPlaying.value) return;
    final total = previewTotal;
    final startedAt = _previewStartedAt;
    if (startedAt == null || total <= Duration.zero) {
      resetPreview();
      return;
    }
    final elapsed = DateTime.now().difference(startedAt);
    previewElapsed.value = elapsed >= total ? total : elapsed;
    var remaining = previewElapsed.value;
    String? current;
    for (final node in _previewNodes) {
      final duration = previewDurationFor(node.id);
      if (remaining < duration) {
        current = node.id;
        break;
      }
      remaining -= duration;
    }
    previewNodeId.value = current ?? _previewNodes.lastOrNull?.id;
    if (elapsed >= total) _stopPreview();
  }

  void _stopPreview() {
    previewPlaying.value = false;
    _previewTimer?.cancel();
    _previewTimer = null;
  }

  void resetPreview() {
    _stopPreview();
    previewElapsed.value = Duration.zero;
    previewNodeId.value = null;
  }
}
