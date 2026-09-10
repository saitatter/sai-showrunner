import 'package:flutter/foundation.dart';
import 'package:sai_nodes/sai_nodes.dart';

/// Provides search, focus, and keyboard cycling for the active graph.
///
/// The service deliberately knows only about editor node IDs and callbacks for
/// ShowRunner's display text and metadata. It does not know about persisted
/// graph IDs, plugin contracts, or widgets.
final class GraphSearchController {
  GraphSearchController({
    required this.controllerProvider,
    required this.titleForNode,
    required this.dataForNode,
  });

  final NodeEditorController Function() controllerProvider;
  final String Function(String editorNodeId) titleForNode;
  final Map<String, dynamic> Function(String editorNodeId) dataForNode;

  final query = ValueNotifier<String>('');
  final matchIndex = ValueNotifier<int>(0);
  final isOpen = ValueNotifier<bool>(false);

  void setQuery(String value) {
    query.value = value.trim();
    matchIndex.value = 0;
  }

  void open() {
    query.value = '';
    isOpen.value = true;
    matchIndex.value = 0;
  }

  void close() {
    isOpen.value = false;
  }

  Set<String> nodeIds([String? requestedQuery]) {
    final normalized = (requestedQuery ?? query.value).toLowerCase();
    final controller = controllerProvider();
    if (normalized.isEmpty) return controller.nodes.keys.toSet();
    return controller.nodes.values
        .where((node) {
          final haystack = [
            titleForNode(node.id),
            node.prototype.idName,
            dataForNode(node.id).toString(),
          ].join(' ').toLowerCase();
          return haystack.contains(normalized);
        })
        .map((node) => node.id)
        .toSet();
  }

  int get resultCount => nodeIds().length;

  void focusResults() {
    final matches = nodeIds();
    if (matches.isNotEmpty) {
      controllerProvider().focusNodesById(matches, animate: false);
    }
  }

  String? focusResult({bool forward = true}) {
    final matches = nodeIds().toList();
    if (matches.isEmpty) {
      matchIndex.value = 0;
      return null;
    }
    final nextIndex = forward
        ? (matchIndex.value + 1) % matches.length
        : (matchIndex.value - 1 + matches.length) % matches.length;
    matchIndex.value = nextIndex;
    final nodeId = matches[nextIndex];
    controllerProvider().focusNodesById({nodeId}, animate: false);
    return nodeId;
  }

  void dispose() {
    query.dispose();
    matchIndex.dispose();
    isOpen.dispose();
  }
}
