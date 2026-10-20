import 'package:sai_nodes_core/sai_nodes_core.dart';
import '../../plugins/registry/plugin_registry.dart';
import '../definitions/showrunner_graph_types.dart';
import '../definitions/showrunner_node_definition_provider.dart';
import '../domain/automation_document.dart';

void validateAutomationContracts(
  AutomationDocument automation,
  DartPluginRegistry registry,
) {
  final definitions = ShowrunnerNodeDefinitionProvider(registry);
  try {
    final resolution = GraphResolver(
      definitions: definitions.definitions,
      types: createShowrunnerGraphTypes(),
    ).resolve(automation.graph);
    final errors = resolution.diagnostics.where(
      (issue) => issue.severity == GraphDiagnosticSeverity.error,
    );
    if (errors.isNotEmpty) {
      throw StateError(
        'Automation cannot execute: ${errors.map((issue) => '${issue.entityId}: ${issue.message}').join('; ')}',
      );
    }
  } finally {
    definitions.dispose();
  }
}
