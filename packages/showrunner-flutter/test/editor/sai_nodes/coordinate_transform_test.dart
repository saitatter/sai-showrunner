import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:showrunner_flutter/editor/sai_nodes/coordinate_transform.dart';

void main() {
  const transform = SaiNodesCoordinateTransform(
    viewportSize: Size(1000, 600),
    viewportOffset: Offset(40, -20),
    zoom: 2,
  );

  test('round-trips world and screen coordinates', () {
    const world = Offset(120, 75);

    expect(transform.screenToWorld(transform.worldToScreen(world)), world);
  });

  test('computes the visible world bounds at the current zoom and pan', () {
    expect(
      transform.visibleWorldBounds,
      const Rect.fromLTWH(-290, -130, 500, 300),
    );
  });
}
