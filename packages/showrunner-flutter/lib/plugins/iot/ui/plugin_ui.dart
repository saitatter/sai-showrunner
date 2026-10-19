import '../../../features/plugins/resource_backed_plugin_workspace.dart';
import '../../registry/plugin_contract.dart';
import '../../registry/plugin_ui.dart';

DartPluginUiContribution createIotPluginUi() => DartFlutterPluginUiContribution(
  builder: (context, host) => ResourceBackedPluginWorkspace(
    pluginId: const PluginId('iot'),
    resourceTypes: {ResourceTypeId('Light'), ResourceTypeId('Plug')},
    dataService: host.dataService,
    registryFuture: host.registryFuture,
    providerEvents: host.providerEvents,
  ),
);
