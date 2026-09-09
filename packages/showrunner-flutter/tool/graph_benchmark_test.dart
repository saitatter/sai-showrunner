import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes/sai_nodes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('records deterministic graph operation timings', () async {
    final results = <Map<String, Object>>[];
    for (final nodeCount in const [100, 500, 1000, 5000]) {
      results.add(await _benchmark(nodeCount));
    }

    for (final result in results) {
      expect(result['nodes'], result['requestedNodes']);
      expect(result['links'], (result['requestedNodes'] as int) - 1);
      expect(result['serializedBytes'], greaterThan(0));
      expect(result['undoRestored'], isTrue);
      expect(result['redoRestored'], isTrue);
    }

    // The JSON line is intentionally machine-readable so CI/nightly jobs can
    // archive it without depending on the Flutter test reporter format.
    // It is a measurement harness, not a flaky wall-clock assertion.
    // ignore: avoid_print
    print('SHOWRUNNER_GRAPH_BENCHMARK ${jsonEncode(results)}');
  });
}

Future<Map<String, Object>> _benchmark(int nodeCount) async {
  final controller = NodeEditorController(
    config: const NodeEditorConfig(
      autoBuildGraph: false,
      autoRunGraph: false,
      enableSnapToGrid: false,
    ),
  );
  controller.registerNodePrototype(_benchmarkPrototype());

  try {
    final loadTimer = Stopwatch()..start();
    for (var index = 0; index < nodeCount; index++) {
      controller.addNode(
        'benchmark',
        offset: Offset((index % 100) * 240, (index ~/ 100) * 120),
      );
    }
    final nodes = controller.nodes.values.toList(growable: false);
    for (var index = 1; index < nodes.length; index++) {
      controller.addLink(nodes[index - 1].id, 'out', nodes[index].id, 'in');
    }
    loadTimer.stop();

    final selectionTimer = Stopwatch()..start();
    controller.selectNodesById(nodes.map((node) => node.id).toSet());
    selectionTimer.stop();

    final dragTimer = Stopwatch()..start();
    controller.dragSelection(const Offset(8, 6), isWorldDelta: true);
    dragTimer.stop();

    controller.history.clear();
    final beforeLayout = <String, Offset>{
      for (final node in nodes) node.id: node.offset,
    };
    final layout = <String, Offset>{
      for (final node in nodes) node.id: node.offset + const Offset(12, 10),
    };
    final layoutTimer = Stopwatch()..start();
    controller.applyLayout(layout);
    layoutTimer.stop();
    await Future<void>.delayed(Duration.zero);

    final serializationTimer = Stopwatch()..start();
    final serialized = controller.project.projectData.toJson(
      controller.project.dataHandlers,
    );
    final serializedBytes = utf8.encode(jsonEncode(serialized)).length;
    serializationTimer.stop();

    final undoTimer = Stopwatch()..start();
    controller.history.undo();
    undoTimer.stop();
    await Future<void>.delayed(Duration.zero);
    final undoRestored = controller.nodes.values.every(
      (node) => node.offset == beforeLayout[node.id],
    );

    final redoTimer = Stopwatch()..start();
    controller.history.redo();
    redoTimer.stop();
    await Future<void>.delayed(Duration.zero);
    final redoRestored = controller.nodes.values.every(
      (node) => node.offset == layout[node.id],
    );

    return {
      'requestedNodes': nodeCount,
      'nodes': controller.nodes.length,
      'links': controller.links.length,
      'serializedBytes': serializedBytes,
      'loadUs': loadTimer.elapsedMicroseconds,
      'selectionUs': selectionTimer.elapsedMicroseconds,
      'dragUs': dragTimer.elapsedMicroseconds,
      'layoutUs': layoutTimer.elapsedMicroseconds,
      'serializationUs': serializationTimer.elapsedMicroseconds,
      'undoUs': undoTimer.elapsedMicroseconds,
      'redoUs': redoTimer.elapsedMicroseconds,
      'undoRestored': undoRestored,
      'redoRestored': redoRestored,
    };
  } finally {
    controller.dispose();
  }
}

NodePrototype _benchmarkPrototype() => NodePrototype(
  idName: 'benchmark',
  displayName: (_) => 'Benchmark node',
  description: (_) => 'Synthetic node used by the graph benchmark.',
  ports: [
    ControlInputPortPrototype(
      idName: 'in',
      displayName: (_) => 'In',
      styleBuilder: defaultPortStyleBuilder,
    ),
    ControlOutputPortPrototype(
      idName: 'out',
      displayName: (_) => 'Out',
      styleBuilder: defaultPortStyleBuilder,
    ),
  ],
  onExecute: (ports, fields, state, forward, put) async {},
);
