import '../../../features/remote/remote_workspace.dart';
import '../../registry/plugin_ui.dart';
import '../../registry/plugin_ui_contract.dart';

DartPluginUiContribution createRemotePluginUi() =>
    DartFlutterPluginUiContribution(
      builder: (context, dataService, providerEvents, registryFuture) =>
          RemoteWorkspace(
            dataService: dataService,
            registryFuture: registryFuture,
          ),
    );
