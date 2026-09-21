part of 'graph_workspace.dart';

// sai_nodes supplies the canvas viewport; this minimap renders ShowRunner
// frames, execution state, and persisted graph links in a compact projection.
class _GraphMinimap extends StatefulWidget {
  const _GraphMinimap({required this.editor});

  final ShowRunnerGraphEditor editor;

  @override
  State<_GraphMinimap> createState() => _GraphMinimapState();
}

class _GraphMinimapState extends State<_GraphMinimap> {
  Size _lastViewportSize = Size.zero;
  bool _hasMeasuredViewport = false;
  bool _layoutRefreshScheduled = false;

  ShowRunnerGraphEditor get editor => widget.editor;

  Size _viewportSize() {
    final renderObject = editor.controller.editorKey.currentContext
        ?.findRenderObject();
    return renderObject is RenderBox && renderObject.hasSize
        ? renderObject.size
        : Size.zero;
  }

  void _refreshAfterLayout(Size viewportSize) {
    if (_layoutRefreshScheduled ||
        (_hasMeasuredViewport && viewportSize == _lastViewportSize)) {
      return;
    }
    _layoutRefreshScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _layoutRefreshScheduled = false;
      if (!mounted) return;
      final measuredSize = _viewportSize();
      if (!_hasMeasuredViewport || measuredSize != _lastViewportSize) {
        _hasMeasuredViewport = true;
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        editor.controller,
        editor.frames,
        editor.executionStates,
      ]),
      builder: (context, child) {
        final nodes = editor.controller.nodes.values.toList();
        final viewportSize = _viewportSize();
        _refreshAfterLayout(viewportSize);
        _lastViewportSize = viewportSize;
        final painter = _GraphMinimapPainter(
          nodes,
          links: editor.controller.linksAsList,
          frames: editor.frames.value,
          executionStates: editor.executionStates.value,
          viewportOffset: editor.controller.viewportOffset,
          viewportZoom: editor.controller.viewportZoom,
          viewportSize: viewportSize,
        );
        return DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xff182126).withValues(alpha: 0.94),
            border: Border.all(color: const Color(0xff475569)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _moveViewportToMinimapPosition(
              editor,
              painter,
              details.localPosition,
            ),
            onPanUpdate: (details) => _moveViewportToMinimapPosition(
              editor,
              painter,
              details.localPosition,
            ),
            child: SizedBox(
              width: 180,
              height: 120,
              child: ClipRect(child: CustomPaint(painter: painter)),
            ),
          ),
        );
      },
    );
  }
}

class _GraphMinimapPainter extends CustomPainter {
  const _GraphMinimapPainter(
    this.nodes, {
    required this.links,
    required this.frames,
    required this.executionStates,
    required this.viewportOffset,
    required this.viewportZoom,
    required this.viewportSize,
  });

  final List<NodeDataModel> nodes;
  final List<LinkDataModel> links;
  final List<NodeFrame> frames;
  final Map<String, GraphNodeExecutionVisual> executionStates;
  final Offset viewportOffset;
  final double viewportZoom;
  final Size viewportSize;

  Rect _nodeBounds(NodeDataModel node) {
    final box = node.key.currentContext?.findRenderObject();
    final size = box is RenderBox && box.hasSize
        ? box.size
        : node.customSize ?? const Size(220, 90);
    return node.offset & size;
  }

  NodeEditorMinimapTransform? get _metrics {
    final bounds = [
      ...nodes.map(_nodeBounds),
      ...frames.map((frame) => frame.bounds),
    ];
    if (bounds.isEmpty) return null;
    return NodeEditorMinimapTransform(
      bounds: bounds.reduce((a, b) => a.expandToInclude(b)),
      size: const Size(180, 120),
    );
  }

  Offset? worldPositionFor(Offset localPosition) {
    final metrics = _metrics;
    if (metrics == null) return null;
    return metrics.minimapToWorld(localPosition);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final metrics = _metrics;
    if (metrics == null) return;
    final paint = Paint()..style = PaintingStyle.fill;
    final framePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xfff472b6);
    for (final frame in frames) {
      canvas.drawRect(_toMiniRect(frame.bounds, metrics), framePaint);
    }
    final linkPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final link in links) {
      final source = nodes
          .where((node) => node.id == link.endpoints.sourceNodeId)
          .firstOrNull;
      final target = nodes
          .where((node) => node.id == link.endpoints.targetNodeId)
          .firstOrNull;
      if (source == null || target == null) continue;
      linkPaint.color = _minimapColor(
        source.prototype.idName,
        executionStates[source.id]?.status,
      ).withValues(alpha: 0.7);
      final sourcePoint = _toMiniPoint(
        source.offset +
            (source.ports[link.endpoints.sourcePortId]?.offset ?? Offset.zero),
        metrics,
      );
      final targetPoint = _toMiniPoint(
        target.offset +
            (target.ports[link.endpoints.targetPortId]?.offset ?? Offset.zero),
        metrics,
      );
      canvas.drawLine(sourcePoint, targetPoint, linkPaint);
    }
    for (final node in nodes) {
      paint.color = _minimapColor(
        node.prototype.idName,
        executionStates[node.id]?.status,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          metrics.worldRectToMinimap(_nodeBounds(node)),
          const Radius.circular(2),
        ),
        paint,
      );
    }
    final viewportWorld = NodeEditorViewportTransform(
      viewportSize: viewportSize,
      viewportOffset: viewportOffset,
      zoom: viewportZoom,
    ).visibleWorldBounds;
    final viewportPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white;
    canvas.drawRect(_toMiniRect(viewportWorld, metrics), viewportPaint);
  }

  Rect _toMiniRect(Rect rect, NodeEditorMinimapTransform metrics) =>
      metrics.worldRectToMinimap(rect);

  Offset _toMiniPoint(Offset point, NodeEditorMinimapTransform metrics) =>
      metrics.worldToMinimap(point);

  @override
  bool shouldRepaint(_GraphMinimapPainter oldDelegate) =>
      oldDelegate.nodes != nodes ||
      oldDelegate.links != links ||
      oldDelegate.frames != frames ||
      oldDelegate.executionStates != executionStates ||
      oldDelegate.viewportOffset != viewportOffset ||
      oldDelegate.viewportZoom != viewportZoom ||
      oldDelegate.viewportSize != viewportSize;
}

Color _minimapColor(String idName, GraphNodeExecutionStatus? status) =>
    switch (status) {
      GraphNodeExecutionStatus.running => const Color(0xff38bdf8),
      GraphNodeExecutionStatus.success => const Color(0xff4ade80),
      GraphNodeExecutionStatus.error => const Color(0xfff87171),
      null => _nodeTypeMinimapColor(idName),
    };

Color _nodeTypeMinimapColor(String idName) => switch (idName) {
  'trigger.twitch.chat' => const Color(0xff60a5fa),
  _ => const Color(0xff94a3b8),
};

void _moveViewportToMinimapPosition(
  ShowRunnerGraphEditor editor,
  _GraphMinimapPainter painter,
  Offset localPosition,
) {
  final worldPosition = painter.worldPositionFor(localPosition);
  if (worldPosition == null) return;
  editor.controller.setViewportOffset(-worldPosition, absolute: true);
}
