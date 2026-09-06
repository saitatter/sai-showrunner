import '../../../features/resources/resource_editor_registry.dart';
import '../../../features/resources/resources_workspace.dart';
import '../../registry/plugin_ui.dart';
import '../../registry/plugin_ui_contract.dart';
import '../manifest.dart';

DartPluginUiContribution createStreamPlansPluginUi({
  DartStreamPlanRuntime? runtime,
}) => DartFlutterPluginUiContribution(
  builder: (context, dataService, providerEvents, registryFuture) =>
      ResourcesWorkspace(
        dataService: dataService,
        editorRegistry: createDefaultResourceEditorRegistry(),
        registryFuture: registryFuture,
        streamPlanRuntime: runtime ?? streamPlanRuntime,
        resourceType: 'StreamPlan',
      ),
);
