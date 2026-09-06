import '../../registry/plugin_ui.dart';
import 'bluesky_workspace.dart';

DartPluginUiContribution createBlueskyPluginUi() =>
    DartFlutterPluginUiContribution(
      builder: (context, dataService, providerEvents, registryFuture) =>
          BlueskyWorkspace(dataService: dataService),
    );
