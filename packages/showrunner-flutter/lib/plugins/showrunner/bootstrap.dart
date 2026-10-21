import '../../runtime/automation_invocation_service.dart';
import '../../graph/runtime/graph_execution_engine.dart';
import 'dart:async';
import '../../graph/domain/automation_document.dart';
import '../../runtime/automation_queue_manager.dart';
import '../../services/showrunner_data_service.dart';
import '../registry/plugin_registry.dart';
import 'manifest.dart';

void registerConfiguredShowRunner(
  DartPluginRegistry registry, {
  required ShowRunnerDataService dataService,
  required DartAutomationQueueManager? queueManager,
  required ShowRunnerAutomationRunner? runAutomation,
  required ShowRunnerProfileActivation? activateProfile,
}) {
  registry.register(
    createShowRunnerPlugin(
      queueManager: queueManager,
      invocations: AutomationInvocationService(
        engine: CompiledExecutionEngine(),
        registry: () => registry,
        queues: queueManager,
      ),
      loadAutomation: (automationId) =>
          _loadAutomationResource(dataService, automationId),
      runAutomation: runAutomation,
      activateProfile: activateProfile,
    ),
  );
}

void registerDefaultShowRunner(
  DartPluginRegistry registry, {
  required DartAutomationQueueManager? queueManager,
  required ShowRunnerAutomationRunner? runAutomation,
  required ShowRunnerProfileActivation? activateProfile,
}) {
  registry.register(
    createShowRunnerPlugin(
      queueManager: queueManager,
      invocations: AutomationInvocationService(
        engine: CompiledExecutionEngine(),
        registry: () => registry,
        queues: queueManager,
      ),
      runAutomation: runAutomation,
      activateProfile: activateProfile,
    ),
  );
}

Future<AutomationDocument?> _loadAutomationResource(
  ShowRunnerDataService dataService,
  String automationId,
) async {
  final normalized = automationId.trim();
  if (normalized.isEmpty ||
      normalized.contains('/') ||
      normalized.contains('\\')) {
    return null;
  }
  final fileName = normalized.endsWith('.yaml')
      ? normalized
      : '$normalized.yaml';
  return dataService.storage.automation(fileName).load();
}
