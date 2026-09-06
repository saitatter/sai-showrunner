import '../../../features/plugins/resource_backed_plugin_workspace.dart';
import '../../registry/plugin_ui.dart';

DartPluginUiContribution createIotPluginUi() => DartFlutterPluginUiContribution(
  builder: (context, dataService, providerEvents, registryFuture) =>
      ResourceBackedPluginWorkspace(
        pluginId: 'iot',
        resourceTypes: const {'Light', 'Plug'},
        dataService: dataService,
        registryFuture: registryFuture,
        providerEvents: providerEvents,
      ),
);
