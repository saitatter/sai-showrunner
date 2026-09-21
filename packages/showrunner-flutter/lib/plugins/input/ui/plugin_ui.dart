import '../../../features/plugins/resource_backed_plugin_workspace.dart';
import '../../registry/plugin_contract.dart';
import '../../registry/plugin_ui.dart';

DartPluginUiContribution createInputPluginUi() =>
    DartFlutterPluginUiContribution(
      builder: (context, host) => ResourceBackedPluginWorkspace(
        pluginId: const PluginId('input'),
        resourceType: const ResourceTypeId('Gamepad'),
        dataService: host.dataService,
        registryFuture: host.registryFuture,
        providerEvents: host.providerEvents,
      ),
    );
