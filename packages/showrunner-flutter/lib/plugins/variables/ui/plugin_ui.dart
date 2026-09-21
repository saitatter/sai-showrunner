import '../../../features/variables/variables_workspace.dart';
import '../../registry/plugin_ui.dart';
import '../runtime.dart';

DartPluginUiContribution createVariablesPluginUi({
  DartVariableRuntime? variableRuntime,
}) => DartFlutterPluginUiContribution(
  builder: (context, host) => VariablesWorkspace(
    dataService: host.dataService,
    eventHub: host.providerEvents.eventHub,
    variableRuntime: variableRuntime,
  ),
);
