import '../../../persistence/viewer_data_repository.dart';
import '../../../features/variables/variables_workspace.dart';
import '../../registry/plugin_ui.dart';
import '../runtime.dart';

DartPluginUiContribution createVariablesPluginUi({
  DartVariableRuntime? variableRuntime,
  ViewerDataRepository? viewerDataRepository,
}) => DartFlutterPluginUiContribution(
  builder: (context, host) => VariablesWorkspace(
    viewerDataRepository: viewerDataRepository,
    dataService: host.dataService,
    eventHub: host.providerEvents.eventHub,
    variableRuntime: variableRuntime,
  ),
);
