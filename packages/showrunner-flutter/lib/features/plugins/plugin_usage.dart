import 'dart:io';

import '../../persistence/automation_repository.dart';
import '../../schema/automation.dart';

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

/// Loads every persisted V2 automation that references [pluginId].
///
/// Usage is intentionally derived at the persistence boundary so the
/// integration details page does not need to know how automation documents
/// are stored. The extractor includes root triggers, graph actions and
/// actions nested in subgraphs, matching the reference application's usage
/// surface.
Future<List<PluginUsageEntry>> loadPluginUsage({
  required Directory directory,
  required String pluginId,
}) async {
  final entries = await AutomationRepository.loadDirectory(directory);
  final usage = <PluginUsageEntry>[];
  for (final entry in entries) {
    final automation = entry.automation;
    if (automation == null) continue;
    final automationName = _automationName(automation, entry.fileName);
    for (final trigger in automation.triggerNodes) {
      if (trigger['plugin']?.toString() != pluginId) continue;
      usage.add(
        PluginUsageEntry(
          automationFile: entry.fileName,
          automationName: automationName,
          kind: 'Trigger',
          name: trigger['trigger']?.toString() ?? '(missing trigger)',
          config: _map(trigger['config']),
        ),
      );
    }
    _addGraphUsage(
      usage,
      automation.graph.nodes,
      pluginId: pluginId,
      automationFile: entry.fileName,
      automationName: automationName,
    );
    for (final subgraph in automation.subgraphs) {
      _addGraphUsage(
        usage,
        subgraph.nodes,
        pluginId: pluginId,
        automationFile: entry.fileName,
        automationName: automationName,
        kindPrefix:
            'Subgraph action · ${subgraph.name.isEmpty ? subgraph.id : subgraph.name}',
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
    if (node.type != 'action' || node.data['plugin']?.toString() != pluginId) {
      continue;
    }
    usage.add(
      PluginUsageEntry(
        automationFile: automationFile,
        automationName: automationName,
        kind: kindPrefix ?? 'Action node',
        name: node.data['action']?.toString() ?? node.id,
        config: _map(node.data['config']),
      ),
    );
  }
}

String _automationName(AutomationData automation, String fileName) {
  final name = automation.extra['name']?.toString().trim();
  return name == null || name.isEmpty ? fileName : name;
}

JsonMap _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{};
