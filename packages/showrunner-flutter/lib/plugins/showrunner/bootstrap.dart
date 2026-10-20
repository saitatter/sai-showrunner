import 'dart:async';
import 'dart:io';
import '../../graph/domain/automation_document.dart';
import '../../persistence/automation_repository.dart';
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
  return AutomationRepository(
    File('${dataService.userDirectory.path}/automations/$fileName'),
  ).load();
}
