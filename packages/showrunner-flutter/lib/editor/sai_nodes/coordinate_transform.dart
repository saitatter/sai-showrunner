import 'package:flutter/widgets.dart';

/// Pure viewport math kept at the `sai_nodes` integration boundary.
///
/// The hosted `sai_nodes` 0.2.0 package exposes viewport state but does not
/// yet expose coordinate conversion methods. Keeping the equations here
/// prevents ShowRunner widgets from depending on RenderBox internals and
/// gives us a small compatibility seam for the upstream API.
final class SaiNodesCoordinateTransform {
  const SaiNodesCoordinateTransform({
    required this.viewportSize,
    required this.viewportOffset,
    required this.zoom,
  }) : assert(zoom > 0);

  final Size viewportSize;
  final Offset viewportOffset;
  final double zoom;

  Offset screenToWorld(Offset screen) => Offset(
    (screen.dx - viewportSize.width / 2) / zoom - viewportOffset.dx,
    (screen.dy - viewportSize.height / 2) / zoom - viewportOffset.dy,
  );

  Offset worldToScreen(Offset world) => Offset(
    viewportSize.width / 2 + (world.dx + viewportOffset.dx) * zoom,
    viewportSize.height / 2 + (world.dy + viewportOffset.dy) * zoom,
  );

  Rect get visibleWorldBounds => Rect.fromLTWH(
    -viewportSize.width / (2 * zoom) - viewportOffset.dx,
    -viewportSize.height / (2 * zoom) - viewportOffset.dy,
    viewportSize.width / zoom,
    viewportSize.height / zoom,
  );
}
