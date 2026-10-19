import '../../registry/plugin_ui.dart';
import 'twitch_workspace.dart';

DartPluginUiContribution createTwitchPluginUi() =>
    DartFlutterPluginUiContribution(
      builder: (context, host) => TwitchWorkspace(
        providerEvents: host.providerEvents,
        registryFuture: host.registryFuture,
        dataService: host.dataService,
      ),
    );
