import '../../graph/runtime/graph_execution_engine.dart';
import '../../persistence/viewer_data_repository.dart';
import '../../runtime/automation_queue_manager.dart';
import '../../services/plugin_event_hub.dart';
import '../showrunner/manifest.dart';
import '../sound/output.dart';
import '../sound/tts_runtime.dart';
import '../stream_plans/manifest.dart';
import 'default_plugin_registrar.dart';
import 'plugin_registry.dart';

export 'configured_plugin_registrar.dart' show createConfiguredPluginRegistry;

DartPluginRegistry createDefaultPluginRegistry({
  DartPluginEventHub? eventHub,
  TtsSpeechService? ttsService,
  SoundOutputRegistry? soundOutputs,
  ViewerDataRepository? viewerDataRepository,
  DartAutomationQueueManager? queueManager,
  GraphExecutionEngine? executionEngine,
  ShowRunnerAutomationRunner? runAutomation,
  ShowRunnerProfileActivation? activateProfile,
  DartStreamPlanRuntime? streamPlans,
}) {
  return buildDefaultPluginRegistry(
    eventHub: eventHub,
    ttsService: ttsService,
    soundOutputs: soundOutputs,
    viewerDataRepository: viewerDataRepository,
    queueManager: queueManager,
    executionEngine: executionEngine,
    runAutomation: runAutomation,
    activateProfile: activateProfile,
    streamPlans: streamPlans,
  );
}
