import '../../../features/plugins/resource_backed_plugin_workspace.dart';
import '../../registry/plugin_contract.dart';
import '../../registry/plugin_ui.dart';

DartPluginUiContribution createDiscordPluginUi() =>
    DartFlutterPluginUiContribution(
      builder: (context, host) => ResourceBackedPluginWorkspace(
        pluginId: const PluginId('discord'),
        resourceType: const ResourceTypeId('DiscordWebhook'),
        dataService: host.dataService,
        registryFuture: host.registryFuture,
        providerEvents: host.providerEvents,
      ),
    );
