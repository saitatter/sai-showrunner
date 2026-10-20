import 'dart:async';
import '../../runtime/expression.dart';
import '../../services/http_provider_transports.dart';
import '../../services/plugin_event_hub.dart';
import '../../services/showrunner_data_service.dart';
import '../registry/plugin_oauth.dart';
import '../registry/plugin_registry.dart';
import 'actions.dart';

Future<void> registerConfiguredYouTube(
  DartPluginRegistry registry, {
  required ShowRunnerDataService dataService,
  required DartPluginEventHub? eventHub,
}) async {
  final youtube = await dataService.loadPluginSettings('youtube');
  final youtubeManager = createPluginTokenManager(
    pluginId: 'youtube',
    settings: youtube,
    dataService: dataService,
    endpoint: 'https://oauth2.googleapis.com/token',
  );
  final youtubeTransport = youtubeManager != null
      ? JsonHttpTransport(
          baseUrl: 'https://www.googleapis.com',
          accessTokenProvider: youtubeManager.accessToken,
        )
      : null;
  registry.register(
    createYouTubePlugin(
      YouTubeTransport(youtubeTransport?.request ?? _unconfiguredYouTube),
      eventHub: eventHub,
    ),

    initialHealth: (youtubeTransport != null)
        ? const DartPluginHealth.connectionUnchecked()
        : const DartPluginHealth.notConfigured(),
  );
}

void registerDefaultYouTube(
  DartPluginRegistry registry, {
  required DartPluginEventHub? eventHub,
}) {
  registry.register(
    createYouTubePlugin(
      YouTubeTransport(_unconfiguredYouTube),
      eventHub: eventHub,
    ),

    initialHealth: const DartPluginHealth.notConfigured(),
  );
}

Future<RuntimeMap> _unconfiguredYouTube(
  String method,
  String path,
  RuntimeMap query,
  dynamic body,
) => Future<RuntimeMap>.error(
  StateError('YouTube transport is not configured.'),
);
