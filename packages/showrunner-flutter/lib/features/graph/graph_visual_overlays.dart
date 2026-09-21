part of 'graph_workspace.dart';

class _GraphAlignmentGuidesOverlay extends StatelessWidget {
  const _GraphAlignmentGuidesOverlay({required this.editor});

  final ShowRunnerGraphEditor editor;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ValueListenableBuilder<List<GraphAlignmentGuide>>(
      valueListenable: editor.alignmentGuides,
      builder: (context, guides, child) => ClipRect(
        child: CustomPaint(
          painter: _GraphAlignmentGuidesPainter(
            guides: guides,
            viewportOffset: editor.controller.viewportOffset,
            viewportZoom: editor.controller.viewportZoom,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
}

class _GraphAlignmentGuidesPainter extends CustomPainter {
  const _GraphAlignmentGuidesPainter({
    required this.guides,
    required this.viewportOffset,
    required this.viewportZoom,
  });

  final List<GraphAlignmentGuide> guides;
  final Offset viewportOffset;
  final double viewportZoom;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || guides.isEmpty) return;
    final transform = NodeEditorViewportTransform(
      viewportSize: size,
      viewportOffset: viewportOffset,
      zoom: viewportZoom,
    );
    final paint = Paint()
      ..color = const Color(0xffff6b6b).withValues(alpha: 0.9)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (final guide in guides) {
      final start = guide.axis == GraphAlignmentAxis.vertical
          ? transform.worldToScreen(Offset(guide.position, guide.from))
          : transform.worldToScreen(Offset(guide.from, guide.position));
      final end = guide.axis == GraphAlignmentAxis.vertical
          ? transform.worldToScreen(Offset(guide.position, guide.to))
          : transform.worldToScreen(Offset(guide.to, guide.position));
      _drawDashedLine(canvas, start, end, paint);
    }
  }

  static void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint,
  ) {
    final delta = end - start;
    final length = delta.distance;
    if (length <= 0) return;
    final direction = delta / length;
    const dash = 4.0;
    const gap = 3.0;
    for (var distance = 0.0; distance < length; distance += dash + gap) {
      final dashEnd = math.min(distance + dash, length);
      canvas.drawLine(
        start + direction * distance,
        start + direction * dashEnd,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GraphAlignmentGuidesPainter oldDelegate) =>
      oldDelegate.guides != guides ||
      oldDelegate.viewportOffset != viewportOffset ||
      oldDelegate.viewportZoom != viewportZoom;
}

// Execution and invalid-link overlays are projections of runtime/schema state;
// they deliberately do not alter sai_nodes' link model.
class _ExecutionLinkOverlay extends StatefulWidget {
  const _ExecutionLinkOverlay({required this.editor});

  final ShowRunnerGraphEditor editor;

  @override
  State<_ExecutionLinkOverlay> createState() => _ExecutionLinkOverlayState();
}

class _GraphFramesOverlay extends StatelessWidget {
  const _GraphFramesOverlay({required this.editor});

  final ShowRunnerGraphEditor editor;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([
      editor.frames,
      editor.selectedFrameId,
      editor.controller.viewportOffsetNotifier,
      editor.controller.viewportZoomNotifier,
    ]),
    builder: (context, child) => LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final canvasBounds = Offset.zero & size;
        return ClipRect(
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _GraphFramesPainter(
                      frames: editor.frames.value,
                      frameColors: {
                        for (final frame in editor.frames.value)
                          frame.id: editor.frameColor(frame.id),
                      },
                      selectedFrameId: editor.selectedFrameId.value,
                      viewportOffset: editor.controller.viewportOffset,
                      viewportZoom: editor.controller.viewportZoom,
                    ),
                  ),
                ),
              ),
              for (final frame in editor.frames.value)
                if (!_frameScreenBounds(
                  frame,
                  size,
                  editor.controller.viewportOffset,
                  editor.controller.viewportZoom,
                ).intersect(canvasBounds).isEmpty)
                  _FrameInteractionLayer(
                    editor: editor,
                    frame: frame,
                    screenBounds: _frameScreenBounds(
                      frame,
                      size,
                      editor.controller.viewportOffset,
                      editor.controller.viewportZoom,
                    ).intersect(canvasBounds),
                  ),
            ],
          ),
        );
      },
    ),
  );
}

class _FrameInteractionLayer extends StatelessWidget {
  const _FrameInteractionLayer({
    required this.editor,
    required this.frame,
    required this.screenBounds,
  });

  final ShowRunnerGraphEditor editor;
  final NodeFrame frame;
  final Rect screenBounds;

  @override
  Widget build(BuildContext context) {
    if (screenBounds.width <= 0 || screenBounds.height <= 0) {
      return const SizedBox.shrink();
    }
    final headerWidth = math.min(screenBounds.width, 220.0);
    // This widget is itself a child of the canvas Stack. Without an explicit
    // Positioned parent, a Stack containing only Positioned children gets no
    // usable layout size and the frame controls become impossible to hit.
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned(
            left: screenBounds.left,
            top: screenBounds.top,
            width: headerWidth,
            height: 34,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => editor.selectFrame(frame.id),
              onPanStart: (_) => editor.selectFrame(frame.id),
              onPanUpdate: (details) => editor.moveFrame(
                frame.id,
                details.delta / editor.controller.viewportZoom,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: screenBounds.right - 22,
            top: screenBounds.bottom - 22,
            width: 22,
            height: 22,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => editor.selectFrame(frame.id),
              onPanStart: (_) => editor.selectFrame(frame.id),
              onPanUpdate: (details) => editor.resizeFrame(
                frame.id,
                details.delta / editor.controller.viewportZoom,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xff101010).withValues(alpha: 0.88),
                  border: Border.all(color: Colors.white38),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Icon(
                  Icons.north_west,
                  size: 14,
                  color: Colors.white70,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GraphFramesPainter extends CustomPainter {
  const _GraphFramesPainter({
    required this.frames,
    required this.frameColors,
    required this.selectedFrameId,
    required this.viewportOffset,
    required this.viewportZoom,
  });

  final List<NodeFrame> frames;
  final Map<String, String> frameColors;
  final String? selectedFrameId;
  final Offset viewportOffset;
  final double viewportZoom;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final frame in frames) {
      final bounds = _frameScreenBounds(
        frame,
        size,
        viewportOffset,
        viewportZoom,
      );
      final selected = frame.id == selectedFrameId;
      final color = _parseFrameColor(frameColors[frame.id] ?? '#64b5f6');
      canvas.drawRRect(
        RRect.fromRectAndRadius(bounds, const Radius.circular(8)),
        Paint()..color = color.withValues(alpha: selected ? 0.08 : 0.035),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bounds, const Radius.circular(8)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2 : 1
          ..color = color.withValues(alpha: selected ? 0.9 : 0.42),
      );
      final label = TextPainter(
        text: TextSpan(
          text: frame.title,
          style: TextStyle(
            color: color.withValues(alpha: selected ? 0.95 : 0.7),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      )..layout(maxWidth: math.max(40, bounds.width - 16));
      label.paint(canvas, Offset(bounds.left + 8, bounds.top + 6));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GraphFramesPainter oldDelegate) =>
      oldDelegate.frames != frames ||
      oldDelegate.frameColors != frameColors ||
      oldDelegate.selectedFrameId != selectedFrameId ||
      oldDelegate.viewportOffset != viewportOffset ||
      oldDelegate.viewportZoom != viewportZoom;
}

Rect _frameScreenBounds(
  NodeFrame frame,
  Size size,
  Offset viewportOffset,
  double viewportZoom,
) => Rect.fromLTRB(
  size.width / 2 + (frame.bounds.left + viewportOffset.dx) * viewportZoom,
  size.height / 2 + (frame.bounds.top + viewportOffset.dy) * viewportZoom,
  size.width / 2 + (frame.bounds.right + viewportOffset.dx) * viewportZoom,
  size.height / 2 + (frame.bounds.bottom + viewportOffset.dy) * viewportZoom,
);

Color _parseFrameColor(String value) {
  final normalized = value.replaceFirst('#', '').trim();
  final hex = normalized.length == 6 ? 'ff$normalized' : normalized;
  final parsed = int.tryParse(hex, radix: 16);
  return parsed == null ? const Color(0xff64b5f6) : Color(parsed);
}

class _ExecutionLinkOverlayState extends State<_ExecutionLinkOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduced) {
      _animationController
        ..stop()
        ..value = 0;
    } else if (!_animationController.isAnimating) {
      _animationController.repeat();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: Listenable.merge([
        widget.editor.controller,
        widget.editor.activeNodeIds,
        widget.editor.executionStates,
        widget.editor.executionEdgeIds,
        widget.editor.controller.viewportOffsetNotifier,
        widget.editor.controller.viewportZoomNotifier,
        _animationController,
      ]),
      builder: (context, child) => ClipRect(
        child: CustomPaint(
          painter: _ExecutionLinkPainter(
            links: widget.editor.controller.linksAsList,
            nodes: widget.editor.controller.nodes,
            executionStates: widget.editor.executionStates.value,
            executionEdgeIds: widget.editor.executionEdgeIds.value,
            schemaLinkId: widget.editor.schemaLinkIdForEditorLink,
            progress: _animationController.value,
            viewportOffset: widget.editor.controller.viewportOffset,
            viewportZoom: widget.editor.controller.viewportZoom,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
}

class _ExecutionLinkPainter extends CustomPainter {
  const _ExecutionLinkPainter({
    required this.links,
    required this.nodes,
    required this.executionStates,
    required this.executionEdgeIds,
    required this.schemaLinkId,
    required this.progress,
    required this.viewportOffset,
    required this.viewportZoom,
  });

  final List<LinkDataModel> links;
  final Map<String, NodeDataModel> nodes;
  final Map<String, GraphNodeExecutionVisual> executionStates;
  final Set<String> executionEdgeIds;
  final String? Function(LinkDataModel link) schemaLinkId;
  final double progress;
  final Offset viewportOffset;
  final double viewportZoom;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    for (final link in links) {
      final source = nodes[link.endpoints.sourceNodeId];
      final target = nodes[link.endpoints.targetNodeId];
      final sourcePort = source?.ports[link.endpoints.sourcePortId];
      final targetPort = target?.ports[link.endpoints.targetPortId];
      if (source == null ||
          target == null ||
          sourcePort == null ||
          targetPort == null) {
        continue;
      }
      final sourceState = executionStates[source.id]?.status;
      final targetState = executionStates[target.id]?.status;
      final exactEdgeId = schemaLinkId(link);
      final hasExactTrace = executionEdgeIds.isNotEmpty;
      final isTraversed = hasExactTrace
          ? exactEdgeId != null && executionEdgeIds.contains(exactEdgeId)
          : sourceState == GraphNodeExecutionStatus.success &&
                (targetState == GraphNodeExecutionStatus.running ||
                    targetState == GraphNodeExecutionStatus.success);
      final isActive =
          isTraversed && targetState == GraphNodeExecutionStatus.running;
      final isCompleted = isTraversed && !isActive;
      final isFailed =
          isTraversed && targetState == GraphNodeExecutionStatus.error;
      if (!isActive && !isCompleted && !isFailed) continue;

      final path = _pathFor(
        _screenPoint(source.offset + sourcePort.offset, size),
        _screenPoint(target.offset + targetPort.offset, size),
      );
      final color = isFailed
          ? const Color(0xfff87171)
          : isActive
          ? const Color(0xff38bdf8)
          : const Color(0xff4ade80);
      if (isActive) {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 8
            ..color = color.withValues(alpha: 0.14)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }
      if (isCompleted) {
        _drawDashedPath(
          canvas,
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = color.withValues(alpha: 0.9),
          progress,
        );
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isActive ? 3.5 : 2.5
          ..color = color.withValues(alpha: isActive ? 0.98 : 0.72),
      );
      if (isActive) {
        final dot = _cubicPoint(path, progress);
        canvas.drawCircle(dot, 5, Paint()..color = color);
        canvas.drawCircle(
          dot,
          9,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = color.withValues(alpha: 0.28),
        );
      }
    }
  }

  Offset _screenPoint(Offset world, Size size) => NodeEditorViewportTransform(
    viewportSize: size,
    viewportOffset: viewportOffset,
    zoom: viewportZoom,
  ).worldToScreen(world);

  Path _pathFor(Offset source, Offset target) {
    final controlOffset = math.min((target.dx - source.dx).abs() / 2, 400);
    return Path()
      ..moveTo(source.dx, source.dy)
      ..cubicTo(
        source.dx + controlOffset,
        source.dy,
        target.dx - controlOffset,
        target.dy,
        target.dx,
        target.dy,
      );
  }

  Offset _cubicPoint(Path path, double value) {
    final metrics = path.computeMetrics().first;
    return metrics.getTangentForOffset(metrics.length * value)!.position;
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint, double progress) {
    final metrics = path.computeMetrics().toList(growable: false);
    if (metrics.isEmpty || metrics.first.length <= 0) return;
    final metric = metrics.first;
    const dashLength = 10.0;
    const gapLength = 7.0;
    final offset = (metric.length * progress) % (dashLength + gapLength);
    for (
      double start = -offset;
      start < metric.length;
      start += dashLength + gapLength
    ) {
      final dashStart = math.max(0, start).toDouble();
      final dashEnd = math.min(metric.length, start + dashLength).toDouble();
      if (dashEnd <= dashStart) continue;
      canvas.drawPath(metric.extractPath(dashStart, dashEnd), paint);
    }
  }

  @override
  bool shouldRepaint(_ExecutionLinkPainter oldDelegate) =>
      oldDelegate.links != links ||
      oldDelegate.nodes != nodes ||
      oldDelegate.executionStates != executionStates ||
      oldDelegate.executionEdgeIds != executionEdgeIds ||
      oldDelegate.progress != progress ||
      oldDelegate.viewportOffset != viewportOffset ||
      oldDelegate.viewportZoom != viewportZoom;
}

class _InvalidLinkOverlay extends StatelessWidget {
  const _InvalidLinkOverlay({required this.editor});

  final ShowRunnerGraphEditor editor;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: Listenable.merge([
        editor.controller,
        editor.nodeRevision,
        editor.activeGraphPath,
        editor.selectedInvalidFlowEdgeId,
        editor.selectedInvalidDataWireId,
      ]),
      builder: (context, child) => ClipRect(
        child: CustomPaint(
          painter: _InvalidLinkPainter(
            flowEdges: editor.invalidFlowEdges,
            dataWires: editor.invalidDataWires,
            nodes: editor.controller.nodes,
            editor: editor,
            viewportOffset: editor.controller.viewportOffset,
            viewportZoom: editor.controller.viewportZoom,
            selectedFlowEdgeId: editor.selectedInvalidFlowEdgeId.value,
            selectedDataWireId: editor.selectedInvalidDataWireId.value,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
}

class _InvalidLinkPainter extends CustomPainter {
  const _InvalidLinkPainter({
    required this.flowEdges,
    required this.dataWires,
    required this.nodes,
    required this.editor,
    required this.viewportOffset,
    required this.viewportZoom,
    required this.selectedFlowEdgeId,
    required this.selectedDataWireId,
  });

  final List<GraphEdge> flowEdges;
  final List<DataWire> dataWires;
  final Map<String, NodeDataModel> nodes;
  final ShowRunnerGraphEditor editor;
  final Offset viewportOffset;
  final double viewportZoom;
  final String? selectedFlowEdgeId;
  final String? selectedDataWireId;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    for (final edge in flowEdges) {
      final path = _flowPath(edge, size);
      if (path != null) {
        _paintInvalidPath(
          canvas,
          path,
          selected: edge.id == selectedFlowEdgeId,
        );
      }
    }
    for (final wire in dataWires) {
      final path = _dataPath(wire, size);
      if (path != null) {
        _paintInvalidPath(
          canvas,
          path,
          selected: wire.id == selectedDataWireId,
        );
      }
    }
  }

  void _paintInvalidPath(Canvas canvas, Path path, {required bool selected}) {
    if (selected) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 9
          ..color = const Color(0xffffc857).withValues(alpha: 0.25),
      );
    }
    _drawDashedPath(
      canvas,
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 3.5 : 2.5
        ..color = selected
            ? const Color(0xffffc857)
            : const Color(0xfff87171).withValues(alpha: 0.92),
    );
  }

  Path? _flowPath(GraphEdge edge, Size size) {
    final source = _nodeForSchemaId(edge.from);
    final target = _nodeForSchemaId(edge.to);
    if (source == null || target == null) return null;
    final sourcePoint = _screenPoint(
      source.offset +
          (_port(
                source,
                edge.port ?? 'completed',
                output: true,
                data: false,
              )?.offset ??
              const Offset(180, 42)),
      size,
    );
    final targetPoint = _screenPoint(
      target.offset +
          (_port(target, 'exec', output: false, data: false)?.offset ??
              const Offset(0, 42)),
      size,
    );
    return _pathFor(sourcePoint, targetPoint);
  }

  Path? _dataPath(DataWire wire, Size size) {
    final source = _nodeForSchemaId(wire.fromNode);
    final target = _nodeForSchemaId(wire.toNode);
    if (source == null || target == null) return null;
    final sourcePoint = _screenPoint(
      source.offset +
          (_port(source, wire.fromPort, output: true, data: true)?.offset ??
              const Offset(180, 42)),
      size,
    );
    final targetPoint = _screenPoint(
      target.offset +
          (_port(target, wire.toPort, output: false, data: true)?.offset ??
              const Offset(0, 42)),
      size,
    );
    return _pathFor(sourcePoint, targetPoint);
  }

  NodeDataModel? _nodeForSchemaId(String schemaId) {
    final editorId = editor.editorNodeIdForSchema(schemaId);
    return editorId == null ? null : nodes[editorId];
  }

  PortDataModel? _port(
    NodeDataModel node,
    String portId, {
    required bool output,
    required bool data,
  }) {
    final expectedDirection = output
        ? PortDirection.output
        : PortDirection.input;
    final expectedType = data ? PortType.data : PortType.control;
    final exact = node.ports[portId];
    if (exact?.prototype.direction == expectedDirection &&
        exact?.prototype.type == expectedType) {
      return exact;
    }
    return node.ports.values
        .where(
          (port) =>
              port.prototype.direction == expectedDirection &&
              port.prototype.type == expectedType,
        )
        .firstOrNull;
  }

  Offset _screenPoint(Offset world, Size size) => NodeEditorViewportTransform(
    viewportSize: size,
    viewportOffset: viewportOffset,
    zoom: viewportZoom,
  ).worldToScreen(world);

  Path _pathFor(Offset source, Offset target) {
    final controlOffset = math.min((target.dx - source.dx).abs() / 2, 400);
    return Path()
      ..moveTo(source.dx, source.dy)
      ..cubicTo(
        source.dx + controlOffset,
        source.dy,
        target.dx - controlOffset,
        target.dy,
        target.dx,
        target.dy,
      );
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      for (var distance = 0.0; distance < metric.length; distance += 12) {
        canvas.drawPath(
          metric.extractPath(distance, math.min(distance + 7, metric.length)),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_InvalidLinkPainter oldDelegate) =>
      oldDelegate.flowEdges != flowEdges ||
      oldDelegate.dataWires != dataWires ||
      oldDelegate.nodes != nodes ||
      oldDelegate.viewportOffset != viewportOffset ||
      oldDelegate.viewportZoom != viewportZoom ||
      oldDelegate.selectedFlowEdgeId != selectedFlowEdgeId ||
      oldDelegate.selectedDataWireId != selectedDataWireId;
}

Widget _buildNodeField(
  BuildContext context,
  FieldDataModel field,
  NodeStyle style,
) {
  final fieldStyle = field.prototype.style;
  return Container(
    padding: fieldStyle.padding,
    decoration: fieldStyle.decoration.copyWith(
      color: const Color(0xff10181d),
      border: Border.all(color: const Color(0xff33434b)),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            field.prototype.displayName(context),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 56,
          child: field.prototype.visualizerBuilder(field.data),
        ),
      ],
    ),
  );
}

Widget _buildNodePort(
  BuildContext context,
  PortDataModel port,
  NodeStyle style,
) {
  final isInput = port.prototype.direction == PortDirection.input;
  final label = Text(
    port.prototype.displayName(context),
    overflow: TextOverflow.ellipsis,
    textAlign: isInput ? TextAlign.left : TextAlign.right,
    style: const TextStyle(color: Colors.white70, fontSize: 11),
  );
  final type = Text(
    _graphPortTypeLabel(port.prototype),
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(
      color: Color(0x80ffffff),
      fontFamily: 'Consolas',
      fontSize: 9,
    ),
  );
  // sai_nodes paints the interactive marker at the actual wire endpoint.
  // Drawing another marker here suggests a second, non-interactive port.
  return Row(
    key: port.key,
    mainAxisSize: MainAxisSize.max,
    mainAxisAlignment: isInput
        ? MainAxisAlignment.start
        : MainAxisAlignment.end,
    children: isInput
        ? [Flexible(child: label), const SizedBox(width: 5), type]
        : [type, const SizedBox(width: 5), Flexible(child: label)],
  );
}

String _graphPortTypeLabel(PortPrototype prototype) {
  if (prototype.type == PortType.control) return 'flow';
  return switch (prototype.dataType.toString()) {
    'String' => 'string',
    'num' => 'number',
    'bool' => 'boolean',
    'List<dynamic>' => 'array',
    'Map<String, dynamic>' => 'object',
    final value => value,
  };
}

class _GraphDropTargetOverlay extends StatelessWidget {
  const _GraphDropTargetOverlay({required this.editor});

  final ShowRunnerGraphEditor editor;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedBuilder(
      animation: Listenable.merge([
        editor.dropTargetLinkId,
        editor.controller,
        editor.controller.viewportOffsetNotifier,
        editor.controller.viewportZoomNotifier,
      ]),
      builder: (context, child) => ClipRect(
        child: CustomPaint(
          painter: _GraphDropTargetPainter(
            linkId: editor.dropTargetLinkId.value,
            nodes: editor.controller.nodes,
            links: editor.controller.links,
            viewportOffset: editor.controller.viewportOffset,
            viewportZoom: editor.controller.viewportZoom,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    ),
  );
}

class _GraphDropTargetPainter extends CustomPainter {
  const _GraphDropTargetPainter({
    required this.linkId,
    required this.nodes,
    required this.links,
    required this.viewportOffset,
    required this.viewportZoom,
  });

  final String? linkId;
  final Map<String, NodeDataModel> nodes;
  final Map<String, LinkDataModel> links;
  final Offset viewportOffset;
  final double viewportZoom;

  @override
  void paint(Canvas canvas, Size size) {
    final id = linkId;
    if (id == null || size.isEmpty) return;
    final link = links[id];
    final source = link == null ? null : nodes[link.endpoints.sourceNodeId];
    final target = link == null ? null : nodes[link.endpoints.targetNodeId];
    final sourcePort = source?.ports[link?.endpoints.sourcePortId];
    final targetPort = target?.ports[link?.endpoints.targetPortId];
    if (source == null ||
        target == null ||
        sourcePort == null ||
        targetPort == null) {
      return;
    }
    final transform = NodeEditorViewportTransform(
      viewportSize: size,
      viewportOffset: viewportOffset,
      zoom: viewportZoom,
    );
    final start = transform.worldToScreen(source.offset + sourcePort.offset);
    final end = transform.worldToScreen(target.offset + targetPort.offset);
    final control = math.min((end.dx - start.dx).abs() / 2, 400);
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(
        start.dx + control,
        start.dy,
        end.dx - control,
        end.dy,
        end.dx,
        end.dy,
      );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 10
        ..color = const Color(0xff2ed47a).withValues(alpha: 0.2),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 4
        ..color = const Color(0xff2ed47a),
    );
  }

  @override
  bool shouldRepaint(_GraphDropTargetPainter oldDelegate) =>
      oldDelegate.linkId != linkId ||
      oldDelegate.nodes != nodes ||
      oldDelegate.links != links ||
      oldDelegate.viewportOffset != viewportOffset ||
      oldDelegate.viewportZoom != viewportZoom;
}

// The remaining widgets are graph-domain panels layered over the canvas.
