import 'package:flutter_test/flutter_test.dart';
import 'package:sai_nodes_core/sai_nodes_core.dart';
import 'package:showrunner_flutter/graph/domain/automation_document.dart';
import 'package:showrunner_flutter/graph/runtime/graph_execution_engine.dart';
import '../support/graph_execution_fixture.dart';

void main() {
  test(
    'memoization uses immutable document identity and exact entry choice',
    () {
      final cache = GraphProgramCache();
      final initial = document(
        [action('a'), action('b')],
        [flow('a', 'b')],
        entry: 'a',
      );
      final first = cache.getOrCompile(initial);
      expect(cache.getOrCompile(initial), same(first));
      expect(cache.signatureBuildCount, 1);
      expect(cache.hitCount, 1);
      final otherEntry = cache.getOrCompile(initial, entryNodeId: 'b');
      expect(otherEntry, isNot(same(first)));
      expect(cache.signatureBuildCount, 2);
      expect(cache.getOrCompile(initial), same(first));
      expect(cache.signatureBuildCount, 3);
      final reconstructed = AutomationDocument.fromJson(initial.toJson());
      expect(cache.getOrCompile(reconstructed), same(first));
      expect(cache.compilationCount, 2);
    },
  );
  test(
    'presentation and host settings preserve payload equality across revisions',
    () {
      final cache = GraphProgramCache();
      final initial = document([action('a')], [], entry: 'a');
      final first = cache.getOrCompile(initial);
      final space = initial.graph.spaces[mainAutomationSpace]!;
      final presented = AutomationDocument.fromGraph(
        initial.graph.copyWith(
          spaces: {
            mainAutomationSpace: space.copyWith(
              nodePresentations: {
                'a': NodePresentation(
                  nodeId: 'a',
                  position: const GraphPoint(90, 50),
                  size: const GraphSize(400, 250),
                ),
              },
            ),
          },
        ),
      );
      expect(cache.getOrCompile(presented), same(first));
      expect(
        cache.getOrCompile(
          presented.withSettings({...presented.settings, 'queue': 'another'}),
        ),
        same(first),
      );
      expect(cache.compilationCount, 1);
    },
  );
  test('action inputs and control wiring always invalidate', () {
    final cache = GraphProgramCache();
    final initial = document(
      [action('a', value: 1), action('b')],
      [flow('a', 'b')],
      entry: 'a',
    );
    final first = cache.getOrCompile(initial);
    final changedInput = document(
      [action('a', value: 2), action('b')],
      [flow('a', 'b')],
      entry: 'a',
    );
    expect(cache.getOrCompile(changedInput), isNot(same(first)));
    final changedFlow = document(
      [action('a', value: 1), action('b')],
      [],
      entry: 'a',
    );
    expect(cache.getOrCompile(changedFlow), isNot(same(first)));
    expect(cache.getOrCompile(initial), same(first));
    expect(cache.compilationCount, 3);
  });
  test('data wiring and dependent subgraph signatures always invalidate', () {
    final cache = GraphProgramCache();
    AutomationDocument fixture(int defaultValue, {bool wired = true}) {
      final sub = AutomationSubgraph(
        id: 'sub',
        name: 'Sub',
        entryNodeId: 'body',
        parameters: [
          AutomationParameter(
            id: 'p',
            name: 'value',
            defaultValue: defaultValue,
          ),
        ],
      );
      return document(
        [action('a', value: 7), action('b')],
        [
          flow('a', 'b'),
          if (wired) wire('a', 'result:value', 'b', 'config:value'),
        ],
        entry: 'a',
        subgraphs: {'sub': sub},
        spaces: {
          sub.spaceId: GraphSpace(
            id: sub.spaceId,
            nodes: {'body': action('body')},
          ),
        },
      );
    }

    final first = cache.getOrCompile(fixture(1));
    expect(cache.getOrCompile(fixture(2)), isNot(same(first)));
    expect(cache.getOrCompile(fixture(1, wired: false)), isNot(same(first)));
    expect(cache.compilationCount, 3);
  });
  test('program and signature memo are bounded and clear together', () {
    final cache = GraphProgramCache(maxEntries: 1);
    final firstDoc = document([action('a')], [], entry: 'a');
    final secondDoc = document([action('b')], [], entry: 'b');
    final first = cache.getOrCompile(firstDoc);
    cache.getOrCompile(secondDoc);
    expect(cache.length, 1);
    expect(cache.getOrCompile(firstDoc), isNot(same(first)));
    expect(cache.signatureBuildCount, 3);
    cache.clear();
    expect(cache.length, 0);
    cache.getOrCompile(firstDoc);
    expect(cache.signatureBuildCount, 4);
    expect(() => GraphProgramCache(maxEntries: -1), throwsArgumentError);
    final disabled = GraphProgramCache(maxEntries: 0);
    disabled.getOrCompile(firstDoc);
    disabled.getOrCompile(firstDoc);
    expect(disabled.length, 0);
    expect(disabled.compilationCount, 2);
  });
}
