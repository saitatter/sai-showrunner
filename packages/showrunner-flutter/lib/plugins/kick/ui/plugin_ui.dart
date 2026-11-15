import '../../registry/plugin_ui.dart';
import 'kick_workspace.dart';

DartPluginUiContribution createKickPluginUi() =>
    DartFlutterPluginUiContribution(
      builder: (context, host) => KickWorkspace(
        dataService: host.dataService,
        providerEvents: host.providerEvents,
        registryFuture: host.registryFuture,
      ),
    );
