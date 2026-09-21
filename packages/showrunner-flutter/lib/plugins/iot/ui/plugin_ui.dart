import '../../../features/plugins/resource_backed_plugin_workspace.dart';
import '../../registry/plugin_ui.dart';

DartPluginUiContribution createIotPluginUi() => DartFlutterPluginUiContribution(
  builder: (context, host) => ResourceBackedPluginWorkspace(
    pluginId: 'iot',
    resourceTypes: const {'Light', 'Plug'},
    dataService: host.dataService,
    registryFuture: host.registryFuture,
    providerEvents: host.providerEvents,
  ),
);
