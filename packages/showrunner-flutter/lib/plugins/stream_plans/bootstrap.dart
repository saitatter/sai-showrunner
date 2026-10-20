import '../../graph/runtime/graph_execution_engine.dart';
import '../../runtime/automation_queue_manager.dart';
import '../registry/plugin_registry.dart';
import 'manifest.dart';

void registerConfiguredStreamPlans(
  DartPluginRegistry registry, {
  required DartAutomationQueueManager? queueManager,
  required GraphExecutionEngine? executionEngine,
  required DartStreamPlanRuntime activeStreamPlans,
  required DartStreamPlanRuntime? streamPlans,
}) {
  registry.register(
    createStreamPlansPlugin(
      runtime: activeStreamPlans,
      registry: registry,
      queueManager: queueManager,
      executionEngine: executionEngine,
    ),
    onStop: streamPlans == null
        ? () => activeStreamPlans.close(registry: registry)
        : null,
  );
}

void registerDefaultStreamPlans(
  DartPluginRegistry registry, {
  required DartAutomationQueueManager? queueManager,
  required GraphExecutionEngine? executionEngine,
  required DartStreamPlanRuntime activeStreamPlans,
  required DartStreamPlanRuntime? streamPlans,
}) {
  registry.register(
    createStreamPlansPlugin(
      runtime: activeStreamPlans,
      registry: registry,
      queueManager: queueManager,
      executionEngine: executionEngine,
    ),
    onStop: streamPlans == null
        ? () => activeStreamPlans.close(registry: registry)
        : null,
  );
}
