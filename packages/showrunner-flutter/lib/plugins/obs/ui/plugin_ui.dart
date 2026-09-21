import '../../registry/plugin_ui.dart';
import 'obs_workspace.dart';

DartPluginUiContribution createObsPluginUi() => DartFlutterPluginUiContribution(
  builder: (context, host) => ObsWorkspace(
    dataService: host.dataService,
    registryFuture: host.registryFuture,
  ),
);
