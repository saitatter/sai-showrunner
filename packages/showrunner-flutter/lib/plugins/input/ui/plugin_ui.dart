import '../../../features/plugins/resource_backed_plugin_workspace.dart';
import '../../registry/plugin_ui.dart';

DartPluginUiContribution createInputPluginUi() =>
    DartFlutterPluginUiContribution(
      builder: (context, host) => ResourceBackedPluginWorkspace(
        pluginId: 'input',
        resourceType: 'Gamepad',
        dataService: host.dataService,
        registryFuture: host.registryFuture,
        providerEvents: host.providerEvents,
      ),
    );
