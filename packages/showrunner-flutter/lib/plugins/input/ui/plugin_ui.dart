import '../../../features/plugins/resource_backed_plugin_workspace.dart';
import '../../registry/plugin_ui.dart';
import '../../registry/plugin_ui_contract.dart';

DartPluginUiContribution createInputPluginUi() =>
    DartFlutterPluginUiContribution(
      builder: (context, dataService, providerEvents, registryFuture) =>
          ResourceBackedPluginWorkspace(
            pluginId: 'input',
            resourceType: 'Gamepad',
            dataService: dataService,
            registryFuture: registryFuture,
            providerEvents: providerEvents,
          ),
    );
