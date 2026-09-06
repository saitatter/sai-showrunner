import '../../../features/variables/variables_workspace.dart';
import '../../registry/plugin_ui.dart';
import '../runtime.dart';

DartPluginUiContribution createVariablesPluginUi({
  DartVariableRuntime? variableRuntime,
}) => DartFlutterPluginUiContribution(
  builder: (context, dataService, providerEvents, registryFuture) =>
      VariablesWorkspace(
        dataService: dataService,
        eventHub: providerEvents.eventHub,
        variableRuntime: variableRuntime,
      ),
);
