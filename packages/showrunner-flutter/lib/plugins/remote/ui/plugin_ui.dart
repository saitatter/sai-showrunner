import '../../../features/remote/remote_workspace.dart';
import '../../registry/plugin_ui.dart';

DartPluginUiContribution createRemotePluginUi() =>
    DartFlutterPluginUiContribution(
      builder: (context, dataService, providerEvents, registryFuture) =>
          RemoteWorkspace(
            dataService: dataService,
            registryFuture: registryFuture,
          ),
    );
