part of 'graph_workspace.dart';

/// Projects transient feedback over the complete card, as in the Electron
/// reference. It never participates in selection or port hit testing.
class _GraphNodeEffects extends StatefulWidget {
  const _GraphNodeEffects({super.key, required this.editor});
  final ShowRunnerGraphEditor editor;

  @override
  State<_GraphNodeEffects> createState() => _GraphNodeEffectsState();
}

class _GraphNodeEffectsState extends State<_GraphNodeEffects>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  late final Listenable _changes = Listenable.merge([
    widget.editor.controller,
    widget.editor.nodeRevision,
    widget.editor.activeNodeIds,
    widget.editor.executionStates,
    widget.editor.previewNodeId,
    widget.editor.searchQuery,
    widget.editor.searchMatchIndex,
    widget.editor.dropTargetNodeId,
    widget.editor.controller.viewportOffsetNotifier,
    widget.editor.controller.viewportZoomNotifier,
  ]);
  bool _portRepaintPending = false;
  int? _portGeometry;
  StreamSubscription<NodeEditorEvent>? _events;

  @override
  void initState() {
    super.initState();
    _changes.addListener(_syncMotion);
    _events = widget.editor.controller.eventBus.events.listen(
      (_) => _queuePortRepaint(),
    );
    _queuePortRepaint();
  }

  void _queuePortRepaint() {
    if (_portRepaintPending) return;
    _portRepaintPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _portRepaintPending = false;
      if (!mounted) return;
      final controller = widget.editor.controller;
      for (final node in controller.nodes.values) {
        final nodeBox = node.key.currentContext?.findRenderObject();
        if (nodeBox is! RenderBox || !nodeBox.hasSize) continue;
        for (final port in node.ports.values) {
          final portBox = port.key.currentContext?.findRenderObject();
          if (portBox is! RenderBox || !portBox.hasSize) continue;
          final point = portBox.localToGlobal(Offset.zero, ancestor: nodeBox);
          port.offset = Offset(
            port.prototype.direction == PortDirection.input
                ? 0
                : nodeBox.size.width,
            node.state.isCollapsed
                ? nodeBox.size.height / 2
                : point.dy + portBox.size.height / 2,
          );
        }
      }
      final geometry = Object.hashAll([
        for (final node in controller.nodes.values) ...[
          node.id,
          for (final port in node.ports.values) port.offset,
        ],
      ]);
      if (_portGeometry == geometry) return;
      _portGeometry = geometry;
      // sai_nodes measures port positions after layout. Publish that new
      // geometry so a freshly opened document does not retain the link paint
      // produced before the endpoints were measured (at node offset zero).
      controller.nodesDataDirty = true;
      controller.linksDataDirty = true;
      // The generic render object listens to canvas events, rather than to
      // ChangeNotifier. Re-publish the unchanged viewport to invalidate its
      // cached link/port painting without moving nodes or recording history.
      controller.eventBus.emit(
        ViewportOffsetEvent(
          controller.viewportOffset,
          id: 'port-layout-$geometry',
          animate: false,
        ),
      );
    });
  }

  void _syncMotion() {
    if (!mounted) return;
    _queuePortRepaint();
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final running = widget.editor.activeNodeIds.value.isNotEmpty;
    if (running && !reduced) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 1;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void dispose() {
    _changes.removeListener(_syncMotion);
    unawaited(_events?.cancel());
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: Listenable.merge([_changes, _pulse]),
      builder: (context, _) => CustomPaint(
        key: const ValueKey('graph-node-effects'),
        painter: _GraphNodeEffectsPainter(
          editor: widget.editor,
          pulse: Curves.easeInOut.transform(_pulse.value),
        ),
        child: const SizedBox.expand(),
      ),
    ),
  );
}

class _GraphNodeEffectsPainter extends CustomPainter {
  _GraphNodeEffectsPainter({required this.editor, required this.pulse});
  final ShowRunnerGraphEditor editor;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final transform = NodeEditorViewportTransform(
      viewportSize: size,
      viewportOffset: editor.controller.viewportOffset,
      zoom: editor.controller.viewportZoom,
    );
    final query = editor.searchQuery.value;
    final matches = query.isEmpty ? <String>{} : editor.searchNodeIds();
    final match = matches.isEmpty
        ? null
        : matches.elementAt(editor.searchMatchIndex.value % matches.length);
    final zoom = editor.controller.viewportZoom;
    for (final node in editor.controller.nodes.values) {
      final box = node.key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final rect = transform.worldToScreen(node.offset) & (box.size * zoom);
      final rounded = RRect.fromRectAndRadius(rect, Radius.circular(6 * zoom));
      if (query.isNotEmpty && !matches.contains(node.id)) {
        canvas.drawRRect(rounded, Paint()..color = const Color(0xb3000000));
      }
      final state = editor.executionStates.value[node.id]?.status;
      final running = editor.activeNodeIds.value.contains(node.id);
      final color = editor.dropTargetNodeId.value == node.id
          ? const Color(0xff2ed47a)
          : running
          ? const Color(0xff4fc3f7)
          : state == GraphNodeExecutionStatus.error
          ? const Color(0xffef5350)
          : state == GraphNodeExecutionStatus.success
          ? const Color(0xff66bb6a)
          : editor.previewNodeId.value == node.id
          ? const Color(0xff2ed47a)
          : match == node.id
          ? const Color(0xffffcc00)
          : null;
      if (color == null) continue;
      final opacity = running ? .7 + .3 * pulse : 1.0;
      canvas.drawRRect(
        rounded.inflate(2 * zoom),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 * zoom
          ..color = color.withValues(alpha: .25 * opacity),
      );
      canvas.drawRRect(
        rounded,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * zoom
          ..color = color.withValues(alpha: opacity),
      );
    }
  }

  // Notifiers contain mutable models; the overlay is already rebuilt only by
  // the relevant notifiers or its running-state animation.
  @override
  bool shouldRepaint(_GraphNodeEffectsPainter oldDelegate) => true;
}
