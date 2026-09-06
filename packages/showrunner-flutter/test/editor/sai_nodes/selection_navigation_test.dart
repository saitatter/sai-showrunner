import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes/sai_nodes.dart';
import 'package:showrunner_flutter/editor/sai_nodes/selection_navigation.dart';

void main() {
  late NodeEditorController controller;
  late SaiNodesSelectionNavigation navigation;

  setUp(() {
    controller = NodeEditorController(
      config: const NodeEditorConfig(
        autoBuildGraph: false,
        autoRunGraph: false,
      ),
    );
    controller.registerNodePrototype(
      NodePrototype(
        idName: 'test.node',
        displayName: (_) => 'Node',
        description: (_) => 'Node',
        onExecute: (_, _, _, _, _) async {},
      ),
    );
    navigation = SaiNodesSelectionNavigation(controller);
  });

  tearDown(() => controller.dispose());

  test('selects the nearest geometrically valid node', () {
    final origin = controller.addNode('test.node', offset: const Offset(0, 0));
    final near = controller.addNode('test.node', offset: const Offset(100, 30));
    controller.addNode('test.node', offset: const Offset(260, 0));
    controller.selectNodesById({origin.id});

    expect(navigation.navigate(SaiNodesNavigationDirection.right), near.id);
    expect(controller.selectedNodeIds, {near.id});
  });

  test('returns null when a direction has no candidate', () {
    final origin = controller.addNode('test.node');
    controller.selectNodesById({origin.id});

    expect(navigation.navigate(SaiNodesNavigationDirection.left), isNull);
    expect(controller.selectedNodeIds, {origin.id});
  });

  test('extends selection without losing the origin', () {
    final origin = controller.addNode('test.node');
    final next = controller.addNode('test.node', offset: const Offset(120, 0));
    controller.selectNodesById({origin.id});

    navigation.navigate(
      SaiNodesNavigationDirection.right,
      extendSelection: true,
    );

    expect(controller.selectedNodeIds, {origin.id, next.id});
  });
}
