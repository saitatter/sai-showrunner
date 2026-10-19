import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/features/resources/overlay/overlay_snapping.dart';

void main() {
  test('move aligns nearest peer edges and scene centers', () {
    final result = snapOverlayBounds(
      bounds: const Rect.fromLTWH(197, 398, 100, 100),
      stage: const Size(1000, 900),
      peers: [const Rect.fromLTWH(300, 80, 200, 150)],
      tolerance: 6,
    );
    expect(result.bounds, const Rect.fromLTWH(200, 400, 100, 100));
    expect(result.vertical, [300]);
    expect(result.horizontal, [450]);
  });
  test(
    'move outside tolerance remains free and scene bounds reject invalid snaps',
    () {
      final result = snapOverlayBounds(
        bounds: const Rect.fromLTWH(122, 133, 100, 100),
        stage: const Size(1000, 900),
        peers: [],
        tolerance: 6,
      );
      expect(result.bounds, const Rect.fromLTWH(122, 133, 100, 100));
      expect(result.vertical, isEmpty);
      expect(result.horizontal, isEmpty);
      final edge = snapOverlayBounds(
        bounds: const Rect.fromLTWH(897, 133, 100, 100),
        stage: const Size(1000, 900),
        peers: [const Rect.fromLTWH(1002, 20, 100, 50)],
        tolerance: 6,
      );
      expect(edge.bounds.right, 1000);
      expect(edge.vertical, [1000]);
    },
  );
  test('resize snaps only moving edges and respects minimum dimensions', () {
    final result = snapOverlayBounds(
      bounds: const Rect.fromLTRB(103, 100, 400, 300),
      stage: const Size(1000, 900),
      peers: [const Rect.fromLTWH(100, 400, 100, 100)],
      tolerance: 6,
      resize: true,
      left: true,
    );
    expect(result.bounds.left, 100);
    expect(result.bounds.right, 400);
    expect(result.bounds.top, 100);
    final minimum = snapOverlayBounds(
      bounds: const Rect.fromLTRB(100, 100, 124, 124),
      stage: const Size(1000, 900),
      peers: [const Rect.fromLTWH(121, 121, 1, 1)],
      tolerance: 6,
      resize: true,
      right: true,
      bottom: true,
    );
    expect(minimum.bounds.size, const Size(24, 24));
    expect(minimum.vertical, isEmpty);
    expect(minimum.horizontal, isEmpty);
  });
}
