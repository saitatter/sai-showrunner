import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes/sai_nodes.dart';

void main() {
  test('classifies persisted graph mutations', () {
    expect(
      isNodeEditorContentMutation(
        const NodeLayoutEvent({'node'}, id: 'layout'),
      ),
      isTrue,
    );
    expect(
      isNodeEditorContentMutation(const ViewportZoomEvent(1.2, id: 'zoom')),
      isFalse,
    );
    expect(
      isNodeEditorContentMutation(
        const NodeSelectionEvent(
          {'node'},
          type: SelectionEventType.select,
          id: 'selection',
        ),
      ),
      isFalse,
    );
  });
}
