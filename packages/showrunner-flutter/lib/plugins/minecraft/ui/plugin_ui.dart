import '../../../features/plugins/resource_backed_plugin_workspace.dart';
import '../../registry/plugin_ui.dart';

DartPluginUiContribution createMinecraftPluginUi() =>
    DartFlutterPluginUiContribution(
      builder: (context, host) => ResourceBackedPluginWorkspace(
        pluginId: 'minecraft',
        resourceType: 'RCONConnection',
        dataService: host.dataService,
        registryFuture: host.registryFuture,
        providerEvents: host.providerEvents,
      ),
    );
