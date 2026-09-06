import '../../../features/plugins/resource_backed_plugin_workspace.dart';
import '../../registry/plugin_ui.dart';

DartPluginUiContribution createDiscordPluginUi() =>
    DartFlutterPluginUiContribution(
      builder: (context, dataService, providerEvents, registryFuture) =>
          ResourceBackedPluginWorkspace(
            pluginId: 'discord',
            resourceType: 'DiscordWebhook',
            dataService: dataService,
            registryFuture: registryFuture,
            providerEvents: providerEvents,
          ),
    );
