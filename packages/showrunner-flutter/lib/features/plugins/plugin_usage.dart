import 'package:sai_nodes_core/sai_nodes_core.dart';
import '../../graph/definitions/showrunner_graph_types.dart';
import '../../graph/domain/automation_document.dart';

import '../../persistence/automation_repository.dart';
import '../../schema/json.dart';

/// A persisted automation location that references one integration plugin.
final class PluginUsageEntry {
  const PluginUsageEntry({
    required this.automationFile,
    required this.automationName,
    required this.kind,
    required this.name,
    this.config = const <String, dynamic>{},
  });

  final String automationFile;
  final String automationName;
  final String kind;
  final String name;
  final JsonMap config;
}

/// Loads every persisted canonical automation that references [pluginId].
///
/// Usage is intentionally derived at the persistence boundary so the
/// integration details page does not need to know how automation documents
/// are stored. The extractor includes root triggers, graph actions and
/// actions nested in subgraphs, matching the reference application's usage
/// surface.
Future<List<PluginUsageEntry>> loadPluginUsage({
  required Future<List<AutomationCatalogEntry>> Function() loadEntries,
  required String pluginId,
}) async {
  final entries = await loadEntries();
  final usage = <PluginUsageEntry>[];
  for (final entry in entries) {
    final automation = entry.automation;
    if (automation == null) continue;
    final automationName = _automationName(automation, entry.fileName);
    for (final space in automation.graph.spaces.values) {
      final signature = automation.subgraphs.values
          .where((signature) => signature.spaceId == space.id)
          .firstOrNull;
      _addGraphUsage(
        usage,
        space.nodes.values,
        pluginId: pluginId,
        automationFile: entry.fileName,
        automationName: automationName,
        kindPrefix: signature == null
            ? null
            : 'Subgraph action · ${signature.name}',
      );
    }
  }
  usage.sort((left, right) {
    final byAutomation = left.automationName.compareTo(right.automationName);
    if (byAutomation != 0) return byAutomation;
    final byKind = left.kind.compareTo(right.kind);
    if (byKind != 0) return byKind;
    return left.name.compareTo(right.name);
  });
  return List.unmodifiable(usage);
}

void _addGraphUsage(
  List<PluginUsageEntry> usage,
  Iterable<GraphNode> nodes, {
  required String pluginId,
  required String automationFile,
  required String automationName,
  String? kindPrefix,
}) {
  for (final node in nodes) {
    final action = decodeContractNodeType(node.type, 'action');
    final trigger = decodeContractNodeType(node.type, 'trigger');
    final contract = action ?? trigger;
    if (contract == null || contract.$1 != pluginId) continue;
    usage.add(
      PluginUsageEntry(
        automationFile: automationFile,
        automationName: automationName,
        kind: kindPrefix ?? (trigger == null ? 'Action node' : 'Trigger'),
        name: contract.$2,
        config: _map(node.data['config']),
      ),
    );
  }
}

String _automationName(AutomationDocument automation, String fileName) {
  final name = automation.metadata['name']?.toString().trim();
  return name == null || name.isEmpty ? fileName : name;
}

JsonMap _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};
