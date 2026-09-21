import '../../registry/plugin_ui.dart';
import 'youtube_workspace.dart';

DartPluginUiContribution createYouTubePluginUi() =>
    DartFlutterPluginUiContribution(
      builder: (context, host) => YouTubeWorkspace(
        dataService: host.dataService,
        providerEvents: host.providerEvents,
        registryFuture: host.registryFuture,
      ),
    );
