import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes/sai_nodes.dart';
import 'package:showrunner_flutter/editor/sai_nodes/content_revision.dart';

void main() {
  test('classifies persisted graph mutations', () {
    expect(
      SaiNodesContentRevision.isContentMutation(
        const NodeLayoutEvent({'node'}, id: 'layout'),
      ),
      isTrue,
    );
    expect(
      SaiNodesContentRevision.isContentMutation(
        const ViewportZoomEvent(1.2, id: 'zoom'),
      ),
      isFalse,
    );
    expect(
      SaiNodesContentRevision.isContentMutation(
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
