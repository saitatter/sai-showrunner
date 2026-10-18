import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/graph/controller/automation_editor_controller.dart';
import '../test/support/graph_fixtures.dart';

void main() {
  test(
    'records immutable host authoring timings and history correctness',
    () async {
      final results = <Map<String, Object>>[];
      for (final count in [100, 500, 1000, 3000, 5000]) {
        final document = automationFixture(
          nodes: [
            for (var i = 0; i < count; i++)
              GraphNode(
                id: 'node-$i',
                type: 'showrunner.if',
                data: {'condition': true},
              ),
          ],
          connections: [
            for (var i = 0; i < count - 1; i++)
              controlFixture(
                'edge-$i',
                'node-$i',
                'node-${i + 1}',
                port: 'flow:then',
              ),
          ],
          entryNodeId: 'node-0',
        );
        final load = Stopwatch()..start();
        final editor = AutomationEditorController(document: document);
        load.stop();
        try {
          final graph = editor.graph;
          expect(graph.resolution.diagnostics, isEmpty);
          final before = graph.document;
          final move = Stopwatch()..start();
          graph.execute(
            MoveNodesCommand(mainAutomationSpace, {
              for (final view in graph.activeSpace!.nodePresentations.values)
                view.nodeId: view.position + const GraphPoint(10, 20),
            }),
          );
          move.stop();
          final moved = graph.document;
          graph.undo();
          expect(graph.document, before);
          graph.redo();
          expect(graph.document, moved);
          final save = Stopwatch()..start();
          final encoded = jsonEncode(editor.document.toJson());
          final restored = AutomationDocument.fromJson(
            Map<String, Object?>.from(jsonDecode(encoded) as Map),
          );
          save.stop();
          expect(restored.graph, graph.document);
          results.add({
            'nodes': count,
            'connections': count - 1,
            'loadUs': load.elapsedMicroseconds,
            'moveUs': move.elapsedMicroseconds,
            'roundTripUs': save.elapsedMicroseconds,
            'serializedBytes': utf8.encode(encoded).length,
            'undoRestored': true,
            'redoRestored': true,
          });
        } finally {
          editor.dispose();
        }
      }
      final file = File('.tmp/benchmarks/host-authoring.json');
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(results),
      );
      // ignore: avoid_print
      print('SHOWRUNNER_GRAPH_BENCHMARK ${jsonEncode(results)}');
    },
  );
}
