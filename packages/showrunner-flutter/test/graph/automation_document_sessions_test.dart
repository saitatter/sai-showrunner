import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes_core/sai_nodes_core.dart';
import 'package:showrunner_flutter/graph/controller/automation_document_sessions.dart';
import 'package:showrunner_flutter/graph/domain/automation_document.dart';

void main() {
  test('camera and selection changes do not rebuild document tabs', () {
    final sessions = AutomationDocumentSessions();
    addTearDown(sessions.dispose);
    final session = sessions.open(AutomationDocument.empty(), 'one.yaml');
    var notices = 0;
    sessions.addListener(() => notices++);
    session.editor.graph.setCamera(
      const GraphCamera(offset: GraphPoint(80, 80), zoom: 2),
    );
    session.editor.graph.select(GraphSelection());
    expect(notices, 0);
    session.editor.addNode('showrunner.if', GraphPoint.zero);
    expect(notices, 1);
    session.editor.addNode('showrunner.return', GraphPoint.zero);
    expect(notices, 1);
    session.editor.updateMetadata({'name': 'Renamed'});
    expect(notices, 2);
  });
  test(
    'tab changes preserve controller identity, history, selection and camera',
    () {
      final sessions = AutomationDocumentSessions();
      addTearDown(sessions.dispose);
      final first = sessions.open(
        AutomationDocument.empty(id: 'first'),
        'first.yaml',
      );
      final nodeId = first.editor.addNode(
        'showrunner.if',
        const GraphPoint(50, 60),
      );
      first.editor.graph.setCamera(
        const GraphCamera(offset: GraphPoint(100, 200), zoom: 1.5),
      );
      final second = sessions.open(
        AutomationDocument.empty(id: 'second'),
        'second.yaml',
      );
      expect(sessions.active, same(second));
      expect(
        sessions.open(AutomationDocument.empty(id: 'ignored'), 'first.yaml'),
        same(first),
      );
      expect(sessions.active!.editor.graph.selection.nodes, {nodeId});
      expect(sessions.active!.editor.graph.camera.zoom, 1.5);
      first.editor.graph.undo();
      expect(first.data.graph.spaces[mainAutomationSpace]!.nodes, isEmpty);
      expect(first.dirty, false);
      first.editor.graph.redo();
      expect(first.dirty, true);
      expect(sessions.hasDirtyDocuments, true);
      expect(second.dirty, false);
    },
  );
  test(
    'saving a captured revision never clears edits made during the write',
    () {
      final sessions = AutomationDocumentSessions();
      addTearDown(sessions.dispose);
      final session = sessions.open(
        AutomationDocument.empty(),
        'one.yaml',
        unsaved: true,
      );
      expect(session.dirty, true);
      session.editor.addNode('showrunner.if', GraphPoint.zero);
      final saving = session.editor.graph.revision;
      session.editor.addNode('showrunner.return', GraphPoint.zero);
      sessions.markSaved('one.yaml', revision: saving);
      expect(session.dirty, true);
      session.editor.graph.undo();
      expect(session.dirty, false);
      expect(sessions.close('one.yaml'), true);
      expect(sessions.active, isNull);
      expect(sessions.hasDocuments, false);
    },
  );
}
