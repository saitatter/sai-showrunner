import '../../../features/remote/remote_workspace.dart';
import '../../registry/plugin_ui.dart';

DartPluginUiContribution createRemotePluginUi() =>
    DartFlutterPluginUiContribution(
      builder: (context, host) => RemoteWorkspace(
        dataService: host.dataService,
        registryFuture: host.registryFuture,
      ),
    );
