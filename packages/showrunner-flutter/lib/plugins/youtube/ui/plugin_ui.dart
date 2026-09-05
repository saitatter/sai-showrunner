import '../../registry/plugin_ui.dart';
import '../../registry/plugin_ui_contract.dart';
import 'youtube_workspace.dart';

DartPluginUiContribution createYouTubePluginUi() =>
    DartFlutterPluginUiContribution(
      builder: (context, dataService, providerEvents, registryFuture) =>
          YouTubeWorkspace(
            dataService: dataService,
            providerEvents: providerEvents,
            registryFuture: registryFuture,
          ),
    );
