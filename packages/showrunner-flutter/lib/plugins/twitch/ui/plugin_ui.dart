import '../../registry/plugin_ui.dart';
import '../../registry/plugin_ui_contract.dart';
import 'twitch_workspace.dart';

DartPluginUiContribution createTwitchPluginUi() =>
    DartFlutterPluginUiContribution(
      builder: (context, dataService, providerEvents, registryFuture) =>
          TwitchWorkspace(
            providerEvents: providerEvents,
            registryFuture: registryFuture,
            dataService: dataService,
          ),
    );
