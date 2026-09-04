import 'dart:io';

import '../../runtime/expression.dart';
import '../../services/plugin_event_hub.dart';
import '../../services/http_provider_transports.dart';
import '../obs/actions.dart';
import 'plugin_registry.dart';
import '../obs/transport.dart';
import '../../services/oauth_token.dart';
import '../../services/showrunner_data_service.dart';
import '../../schema/automation.dart';
import '../twitch/actions.dart';
import '../youtube/actions.dart';
import '../moderation/moderation.dart';
import '../moderation/runtime.dart';
import '../discord/manifest.dart';
import '../sound/manifest.dart';
import '../sound/output.dart';
import '../minecraft/manifest.dart';
import '../http/manifest.dart';
import '../time/manifest.dart';
import '../os/manifest.dart';
import '../random/manifest.dart';
import '../variables/manifest.dart';
import '../overlays/manifest.dart';
import '../spellcast/manifest.dart';
import '../iot/manifest.dart';
import '../input/manifest.dart';
import '../stream_plans/manifest.dart';
import '../showrunner/manifest.dart';
import '../sound/tts_runtime.dart';
import '../../persistence/viewer_data_repository.dart';

DartPluginRegistry createDefaultPluginRegistry({
  DartPluginEventHub? eventHub,
  TtsSpeechService? ttsService,
  SoundOutputRegistry? soundOutputs,
  ViewerDataRepository? viewerDataRepository,
}) {
  final variablesRepository =
      viewerDataRepository ?? InMemoryViewerDataRepository();
  final registry = DartPluginRegistry();
  registry.register(createShowRunnerPlugin());
  registry.register(createObsPlugin(CallbackObsTransport(_unconfiguredObs)));
  registry.register(
    createYouTubePlugin(
      YouTubeTransport(_unconfiguredYouTube),
      eventHub: eventHub,
    ),
  );
  registry.register(
    createTwitchPlugin(
      TwitchTransport(_unconfiguredTwitch),
      eventHub: eventHub,
    ),
  );
  registry.register(createDiscordPlugin());
  registry.register(
    createSoundPlugin(ttsService: ttsService, soundOutputs: soundOutputs),
  );
  registry.register(createMinecraftPlugin());
  registry.register(createHttpPlugin());
  registry.register(createTimePlugin());
  registry.register(createOsPlugin());
  registry.register(createRandomPlugin());
  registry.register(
    createVariablesPlugin(
      viewerDataRepository: variablesRepository,
      eventHub: eventHub,
    ),
  );
  registry.register(createOverlaysPlugin());
  registry.register(createSpellcastPlugin(eventHub: eventHub));
  registry.register(createIotPlugin());
  registry.register(createInputPlugin());
  registry.register(createStreamPlansPlugin());
  return registry;
}

Future<DartPluginRegistry> createConfiguredPluginRegistry(
  ShowRunnerDataService dataService, {
  DartPluginEventHub? eventHub,
  TtsSpeechService? ttsService,
  SoundOutputRegistry? soundOutputs,
  ViewerDataRepository? viewerDataRepository,
}) async {
  final variablesRepository =
      viewerDataRepository ??
      FileViewerDataRepository(
        Directory('${dataService.userDirectory.path}/viewer-data'),
      );
  final obs = await dataService.loadPluginSettings('obs');
  final youtube = await dataService.loadPluginSettings('youtube');
  final twitch = await dataService.loadPluginSettings('twitch');
  final appSettings = await dataService.loadPluginSettings(
    'showrunner-flutter',
  );
  final registry = DartPluginRegistry();
  registry.register(createShowRunnerPlugin());
  final host = obs['host'] as String?;
  final port = (obs['port'] as num?)?.toInt();
  registry.register(
    host != null && port != null
        ? createObsPlugin(
            ObsWebSocketTransport(
              host: host,
              port: port,
              password: obs['password'] as String?,
            ),
          )
        : createObsPlugin(CallbackObsTransport(_unconfiguredObs)),
  );
  final twitchClientId = twitch['clientId'] as String?;
  final youtubeManager = _createTokenManager(
    pluginId: 'youtube',
    settings: youtube,
    dataService: dataService,
    endpoint: 'https://oauth2.googleapis.com/token',
  );
  final twitchManager = _createTokenManager(
    pluginId: 'twitch',
    settings: twitch,
    dataService: dataService,
    endpoint: 'https://id.twitch.tv/oauth2/token',
  );
  final youtubeTransport = youtubeManager != null
      ? JsonHttpTransport(
          baseUrl: 'https://www.googleapis.com',
          accessTokenProvider: youtubeManager.accessToken,
        )
      : null;
  final twitchTransport = twitchManager != null
      ? JsonHttpTransport(
          baseUrl: 'https://api.twitch.tv',
          accessTokenProvider: twitchManager.accessToken,
          headers: {
            if (twitchClientId != null && twitchClientId.isNotEmpty)
              'Client-Id': twitchClientId,
          },
        )
      : null;
  registry.register(
    createYouTubePlugin(
      YouTubeTransport(youtubeTransport?.request ?? _unconfiguredYouTube),
      eventHub: eventHub,
    ),
  );
  registry.register(
    createTwitchPlugin(
      TwitchTransport((method, path, query, body) async {
        if (twitchTransport == null) {
          return _unconfiguredTwitch(method, path, query, body);
        }
        return twitchTransport.request(method, path, query, body);
      }),
      eventHub: eventHub,
    ),
  );
  final moderationService = ModerationService(dataService: dataService);
  registry.register(createModerationPlugin(moderationService));
  registry.register(createDiscordPlugin());
  registry.register(
    createSoundPlugin(ttsService: ttsService, soundOutputs: soundOutputs),
  );
  registry.register(createMinecraftPlugin());
  registry.register(createHttpPlugin());
  registry.register(createTimePlugin());
  registry.register(createOsPlugin());
  registry.register(createRandomPlugin());
  registry.register(
    createVariablesPlugin(
      viewerDataRepository: variablesRepository,
      eventHub: eventHub,
    ),
  );
  registry.register(createOverlaysPlugin());
  registry.register(createSpellcastPlugin(eventHub: eventHub));
  registry.register(createIotPlugin());
  registry.register(createInputPlugin());
  registry.register(createStreamPlansPlugin());
  final disabled = appSettings['disabledPlugins'];
  if (disabled is List) {
    for (final pluginId in disabled.whereType<String>()) {
      registry.setPluginEnabled(pluginId, false);
    }
  }
  return registry;
}

OAuthTokenManager? _createTokenManager({
  required String pluginId,
  required JsonMap settings,
  required ShowRunnerDataService dataService,
  required String endpoint,
}) {
  final accessToken = settings['accessToken'] as String?;
  final refreshToken = settings['refreshToken'] as String?;
  final clientId = settings['clientId'] as String?;
  final clientSecret = settings['clientSecret'] as String?;
  if ((accessToken?.isNotEmpty != true && refreshToken?.isNotEmpty != true) ||
      clientId?.isNotEmpty != true ||
      clientSecret?.isNotEmpty != true) {
    return null;
  }
  final rawExpiry = settings['expiresAt'];
  final expiresAt = rawExpiry is String ? DateTime.tryParse(rawExpiry) : null;
  final manager = OAuthTokenManager(
    current: OAuthTokenSet(
      accessToken: accessToken ?? '',
      refreshToken: refreshToken,
      expiresAt: expiresAt,
    ),
    refresh: (token) async {
      final next = await const OAuthTokenClient().refresh(
        tokenEndpoint: endpoint,
        clientId: clientId!,
        clientSecret: clientSecret!,
        refreshToken: token,
      );
      await dataService.savePluginSettings(pluginId, {
        ...settings,
        'accessToken': next.accessToken,
        if (next.refreshToken != null) 'refreshToken': next.refreshToken,
        if (next.expiresAt != null)
          'expiresAt': next.expiresAt!.toIso8601String(),
      });
      return next;
    },
  );
  return manager;
}

Future<RuntimeMap> _unconfiguredObs(String request, RuntimeMap data) =>
    Future<RuntimeMap>.error(StateError('OBS transport is not configured.'));

Future<RuntimeMap> _unconfiguredYouTube(
  String method,
  String path,
  RuntimeMap query,
  dynamic body,
) => Future<RuntimeMap>.error(
  StateError('YouTube transport is not configured.'),
);

Future<RuntimeMap> _unconfiguredTwitch(
  String method,
  String path,
  RuntimeMap query,
  RuntimeMap body,
) =>
    Future<RuntimeMap>.error(StateError('Twitch transport is not configured.'));
