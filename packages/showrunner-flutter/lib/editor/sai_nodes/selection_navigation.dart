import 'package:sai_nodes/sai_nodes.dart';

/// Direction understood by a generic `sai_nodes` selection navigator.
///
/// Keyboard mapping stays in the host because key bindings are a Flutter
/// concern; geometric selection does not know anything about ShowRunner.
enum SaiNodesNavigationDirection { left, right, up, down }

/// Compatibility adapter for the navigation API that will eventually live in
/// `sai_nodes` itself.
///
/// The hosted `sai_nodes` 0.2.0 controller already owns node state and
/// selection. Keeping this algorithm in a controller-facing adapter lets the
/// ShowRunner editor stop carrying generic geometry while preserving the
/// public package boundary until the upstream API is released.
final class SaiNodesSelectionNavigation {
  const SaiNodesSelectionNavigation(this.controller);

  final NodeEditorController controller;

  String? navigate(
    SaiNodesNavigationDirection direction, {
    bool extendSelection = false,
  }) {
    if (controller.selectedNodeIds.isEmpty) return null;
    final currentId = controller.selectedNodeIds.last;
    final current = controller.nodes[currentId];
    if (current == null) return null;

    NodeDataModel? best;
    var bestScore = double.infinity;
    for (final candidate in controller.nodes.values) {
      if (candidate.id == current.id) continue;
      final delta = candidate.offset - current.offset;
      final inDirection = switch (direction) {
        SaiNodesNavigationDirection.right => delta.dx > 20,
        SaiNodesNavigationDirection.left => delta.dx < -20,
        SaiNodesNavigationDirection.down => delta.dy > 20,
        SaiNodesNavigationDirection.up => delta.dy < -20,
      };
      if (!inDirection) continue;

      final primaryDistance = switch (direction) {
        SaiNodesNavigationDirection.right => delta.dx,
        SaiNodesNavigationDirection.left => -delta.dx,
        SaiNodesNavigationDirection.down => delta.dy,
        SaiNodesNavigationDirection.up => -delta.dy,
      };
      final crossDistance =
          direction == SaiNodesNavigationDirection.left ||
              direction == SaiNodesNavigationDirection.right
          ? delta.dy.abs()
          : delta.dx.abs();
      final score = primaryDistance + crossDistance * 2;
      if (score < bestScore) {
        bestScore = score;
        best = candidate;
      }
    }

    if (best == null) return null;
    controller.selectNodesById({best.id}, holdSelection: extendSelection);
    return best.id;
  }
}
