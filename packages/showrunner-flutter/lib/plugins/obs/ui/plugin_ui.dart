import '../../registry/plugin_ui.dart';
import 'obs_workspace.dart';

DartPluginUiContribution createObsPluginUi() => DartFlutterPluginUiContribution(
  builder: (context, dataService, providerEvents, registryFuture) =>
      ObsWorkspace(dataService: dataService, registryFuture: registryFuture),
);
