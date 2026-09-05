import 'dart:io';

import 'dart:async';

import '../../runtime/expression.dart';
import '../../services/plugin_event_hub.dart';
import '../../services/http_provider_transports.dart';
import '../obs/actions.dart';
import '../obs/ui/plugin_ui.dart';
import 'plugin_registry.dart';
import 'plugin_host_context.dart';
import '../obs/connection_router.dart';
import '../../services/oauth_token.dart';
import '../../services/showrunner_data_service.dart';
import '../../schema/automation.dart';
import '../../runtime/automation_queue_manager.dart';
import '../twitch/actions.dart';
import '../twitch/ui/plugin_ui.dart';
import '../youtube/actions.dart';
import '../youtube/ui/plugin_ui.dart';
import '../moderation/moderation.dart';
import '../moderation/runtime.dart';
import '../moderation/ui/plugin_ui.dart';
import '../discord/manifest.dart';
import '../bluesky/manifest.dart';
import '../donordrive/manifest.dart';
import '../aitum/manifest.dart';
import '../advss/manifest.dart';
import '../remote/manifest.dart';
import '../voicemod/manifest.dart';
import '../sound/manifest.dart';
import '../sound/output.dart';
import '../sound/windows_audio.dart';
import '../minecraft/manifest.dart';
import '../http/manifest.dart';
import '../time/manifest.dart';
import '../os/manifest.dart';
import '../random/manifest.dart';
import '../variables/manifest.dart';
import '../overlays/manifest.dart';
import '../overlays/websocket_bridge.dart';
import '../spellcast/manifest.dart';
import '../spellcast/ui/plugin_ui.dart';
import '../iot/manifest.dart';
import 'configured_iot_resolver.dart';
import '../govee/manifest.dart';
import '../philips_hue/manifest.dart';
import '../twinkly/manifest.dart';
import '../elgato/manifest.dart';
import '../tplink_kasa/manifest.dart';
import '../lifx/manifest.dart';
import '../wyze/manifest.dart';
import '../dashboards/manifest.dart';
import '../input/manifest.dart';
import '../stream_plans/manifest.dart';
import '../showrunner/manifest.dart';
import '../sound/tts_runtime.dart';
import '../../persistence/viewer_data_repository.dart';
import '../../persistence/resource_repository.dart';
import '../../persistence/profile_repository.dart';
import '../../persistence/automation_repository.dart';

part 'default_plugin_registrar.dart';

DartPluginRegistry createDefaultPluginRegistry({
  DartPluginEventHub? eventHub,
  TtsSpeechService? ttsService,
  SoundOutputRegistry? soundOutputs,
  ViewerDataRepository? viewerDataRepository,
  DartAutomationQueueManager? queueManager,
  ShowRunnerAutomationRunner? runAutomation,
  ShowRunnerProfileActivation? activateProfile,
}) {
  return buildDefaultPluginRegistry(
    eventHub: eventHub,
    ttsService: ttsService,
    soundOutputs: soundOutputs,
    viewerDataRepository: viewerDataRepository,
    queueManager: queueManager,
    runAutomation: runAutomation,
    activateProfile: activateProfile,
  );
}

Future<DartPluginRegistry> createConfiguredPluginRegistry(
  ShowRunnerDataService dataService, {
  DartPluginEventHub? eventHub,
  TtsSpeechService? ttsService,
  SoundOutputRegistry? soundOutputs,
  ViewerDataRepository? viewerDataRepository,
  DartAutomationQueueManager? queueManager,
  ShowRunnerAutomationRunner? runAutomation,
  ShowRunnerProfileActivation? activateProfile,
}) async {
  final variablesRepository =
      viewerDataRepository ??
      FileViewerDataRepository(
        Directory('${dataService.userDirectory.path}/viewer-data'),
      );
  final youtube = await dataService.loadPluginSettings('youtube');
  final twitch = await dataService.loadPluginSettings('twitch');
  final interfaceSettings = await dataService.loadPluginSettings(
    'showrunner-flutter',
  );
  final showRunnerSettings = await dataService.loadPluginSettings('ShowRunner');
  final appSettings = <String, dynamic>{
    ...interfaceSettings,
    ...showRunnerSettings,
  };
  final httpEndpointService = DartHttpEndpointService(
    port: _port(appSettings['port'], 8181),
  );
  final registry = DartPluginRegistry();
  registry.register(
    createShowRunnerPlugin(
      queueManager: queueManager,
      loadAutomation: (automationId) =>
          _loadAutomationResource(dataService, automationId),
      runAutomation: runAutomation,
      activateProfile: activateProfile,
    ),
  );
  final obsTransport = ObsConnectionRouter(
    dataService: dataService,
    eventHub: eventHub,
    onStateChanged: (state, value) => registry.updateState('obs', state, value),
  );
  registry.register(createObsPlugin(obsTransport));
  registry.registerUi('obs', createObsPluginUi());
  registry.register(createAitumPlugin(obsTransport));
  registry.register(createAdvssPlugin(obsTransport, eventHub: eventHub));
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
  registry.registerUi('youtube', createYouTubePluginUi());
  final configuredTwitchTransport = TwitchTransport((
    method,
    path,
    query,
    body,
  ) async {
    if (twitchTransport == null) {
      return _unconfiguredTwitch(method, path, query, body);
    }
    return twitchTransport.request(method, path, query, body);
  });
  registry.register(
    createTwitchPlugin(
      configuredTwitchTransport,
      eventHub: eventHub,
      viewerGroupRepository: ResourceRepository(
        Directory('${dataService.userDirectory.path}/twitch/groups'),
      ),
    ),
  );
  registry.registerUi('twitch', createTwitchPluginUi());
  _registerTwitchStreamPlanComponent(
    transport: configuredTwitchTransport,
    broadcasterId: twitch['broadcasterId']?.toString(),
  );
  final moderationService = ModerationService(dataService: dataService);
  registry.register(createModerationPlugin(moderationService));
  registry.registerUi(
    'moderation',
    createModerationPluginUi(moderationService),
  );
  registry.register(createDiscordPlugin());
  final blueskySettings = await dataService.loadPluginSettings('bluesky');
  final blueskyIdentifier = blueskySettings['identifier']?.toString().trim();
  final blueskyPassword = blueskySettings['appPassword']?.toString().trim();
  final blueskyServiceUrl = blueskySettings['serviceUrl']?.toString().trim();
  final blueskyHttp = BlueskyHttpTransport(
    baseUrl: blueskyServiceUrl?.isNotEmpty == true
        ? blueskyServiceUrl!
        : 'https://bsky.social',
  );
  registry.register(
    createBlueskyPlugin(
      BlueskyTransport(blueskyHttp.post),
      identifier: blueskyIdentifier,
      appPassword: blueskyPassword,
    ),
  );
  final donorDriveSettings = await dataService.loadPluginSettings('donordrive');
  final donorDriveApiBase = donorDriveSettings['apiBase']?.toString().trim();
  final donorDriveParticipant = donorDriveSettings['participantId']
      ?.toString()
      .trim();
  final donorDriveInterval = _positiveDuration(
    donorDriveSettings['pollIntervalSeconds'],
    const Duration(seconds: 15),
  );
  final donorDriveRuntime =
      eventHub != null && donorDriveParticipant?.isNotEmpty == true
      ? DonorDriveRuntime(
          transport: DonorDriveTransport(
            DonorDriveHttpTransport(
              baseUrl: donorDriveApiBase?.isNotEmpty == true
                  ? donorDriveApiBase!
                  : 'https://www.extra-life.org/api',
            ).request,
          ),
          eventHub: eventHub,
          apiBase: donorDriveApiBase ?? 'https://www.extra-life.org/api',
          participantId: donorDriveParticipant!,
          pollInterval: donorDriveInterval,
        )
      : null;
  registry.register(createDonorDrivePlugin(donorDriveRuntime));
  final remoteSettings = await dataService.loadPluginSettings('remote');
  final remoteEnabled = remoteSettings['enabled'] == true;
  final remoteHost = remoteSettings['host']?.toString().trim();
  final remotePort = _port(remoteSettings['port'], 8390);
  final remoteRuntime = remoteEnabled && eventHub != null
      ? RemoteButtonRuntime(
          eventHub: eventHub,
          host: remoteHost?.isNotEmpty == true ? remoteHost! : '127.0.0.1',
          port: remotePort,
          loadButtonNames: () => _loadRemoteButtonNames(dataService),
          onStateChanged: (state) =>
              registry.updateState('remote', 'server', state),
        )
      : null;
  registry.register(
    createRemotePlugin(eventHub: eventHub, runtime: remoteRuntime),
  );
  final voiceModSettings = await dataService.loadPluginSettings('voicemod');
  final voiceModHost = voiceModSettings['host']?.toString().trim();
  final voiceModTransport = VoiceModWebSocketTransport(
    host: voiceModHost?.isNotEmpty == true ? voiceModHost! : '127.0.0.1',
    port: _port(voiceModSettings['port'], 59129),
  );
  final soundSettings = await dataService.loadPluginSettings('sound');
  final defaultOutput = soundSettings['defaultOutput']?.toString().trim();
  final configuredSoundOutputs =
      soundOutputs ??
      createDefaultSoundOutputRegistry(defaultOutputId: defaultOutput);
  if (soundOutputs != null && defaultOutput?.isNotEmpty == true) {
    configuredSoundOutputs.defaultOutputId = defaultOutput;
  }
  if (soundOutputs == null) {
    final splitters = await ResourceRepository(
      Directory('${dataService.userDirectory.path}/sound/splitters'),
    ).list();
    for (final splitter in splitters) {
      configuredSoundOutputs.registerSplitterConfig(
        splitter.id,
        splitter.config,
      );
    }
  }
  registry.register(createVoiceModPlugin(voiceModTransport));
  registry.register(
    createSoundPlugin(
      ttsService: ttsService,
      soundOutputs: configuredSoundOutputs,
      ttsVoiceResolver: (id) async {
        final resource = await ResourceRepository(
          Directory('${dataService.userDirectory.path}/sound/tts'),
        ).load(id);
        return resource?.config;
      },
      globalVolume: _percentage(soundSettings['globalVolume'], 100),
    ),
  );
  registry.register(createMinecraftPlugin());
  registry.register(
    createHttpPlugin(eventHub: eventHub, endpointService: httpEndpointService),
  );
  registry.register(createTimePlugin());
  registry.register(createOsPlugin());
  registry.register(createRandomPlugin(eventHub: eventHub));
  registry.register(
    createVariablesPlugin(
      viewerDataRepository: variablesRepository,
      eventHub: eventHub,
    ),
  );
  final overlayRepository = ResourceRepository(
    Directory('${dataService.userDirectory.path}/overlays'),
  );
  final overlayStore = OverlayResourceStore(
    load: overlayRepository.load,
    save: overlayRepository.save,
  );
  final overlayBridge = eventHub == null
      ? null
      : DartOverlayWebSocketService(
          server: httpEndpointService,
          eventHub: eventHub,
          overlayStore: overlayStore,
          registry: registry,
          viewerDataRepository: variablesRepository,
          soundOutputs: configuredSoundOutputs,
          mediaRoot: Directory('${dataService.userDirectory.path}/media'),
          ttsRoot: Directory('${Directory.systemTemp.path}/ShowRunner-tts'),
        );
  if (overlayBridge != null) {
    for (final resource in await overlayRepository.list()) {
      overlayBridge.registerAudioOutput(resource.id);
    }
  }
  registry.register(
    createOverlaysPlugin(
      eventHub: eventHub,
      overlayStore: overlayStore,
      onDispose: overlayBridge?.dispose,
    ),
  );
  final spellcastHub = eventHub ?? DartPluginEventHub();
  registry.register(createSpellcastPlugin(eventHub: spellcastHub));
  registry.registerUi('spellcast', createSpellcastPluginUi(spellcastHub));
  final goveeSettings = await dataService.loadPluginSettings('govee');
  final goveeApiKey = goveeSettings['apiKey'] as String?;
  final goveeTransport = goveeApiKey?.isNotEmpty == true
      ? JsonHttpTransport(
          baseUrl: 'https://developer-api.govee.com',
          headers: {'Govee-API-KEY': goveeApiKey!},
        )
      : null;
  registry.register(
    createGoveePlugin(
      GoveeTransport(goveeTransport?.request ?? _unconfiguredGovee),
    ),
  );
  final hueSettings = await dataService.loadPluginSettings('philips-hue');
  final hueIp = hueSettings['hubIp']?.toString().trim() ?? '';
  final hueKey = hueSettings['hubKey']?.toString().trim() ?? '';
  final hueTransport = hueIp.isNotEmpty && hueKey.isNotEmpty
      ? HueHttpTransport(host: hueIp, applicationKey: hueKey)
      : null;
  final configuredHueTransport = HueTransport(
    hueTransport?.request ?? _unconfiguredPhilipsHue,
  );
  registry.register(
    createPhilipsHuePlugin(
      configuredHueTransport,
      transportResolver: (config) {
        final host = config['host']?.toString().trim() ?? '';
        final key = config['hubKey']?.toString().trim() ?? '';
        if (host.isEmpty || (key.isEmpty && hueKey.isEmpty)) {
          return configuredHueTransport;
        }
        return HueTransport(
          HueHttpTransport(
            host: host,
            applicationKey: key.isEmpty ? hueKey : key,
          ).request,
        );
      },
    ),
  );
  final twinklyTransport = TwinklyHttpTransport();
  registry.register(
    createTwinklyPlugin(TwinklyTransport(twinklyTransport.request)),
  );
  final elgatoSettings = await dataService.loadPluginSettings('elgato');
  final elgatoHost = elgatoSettings['host']?.toString().trim();
  final elgatoPort = _port(elgatoSettings['port'], 9123);
  final elgatoLights = _positiveInt(elgatoSettings['numberOfLights'], 1);
  final elgatoRgb =
      elgatoSettings['rgb'] == true ||
      elgatoSettings['rgb']?.toString().toLowerCase() == 'true';
  final elgatoTransport = elgatoHost?.isNotEmpty == true
      ? ElgatoHttpTransport(host: elgatoHost!, port: elgatoPort)
      : null;
  final configuredElgatoTransport = ElgatoTransport(
    elgatoTransport?.request ?? _unconfiguredElgato,
  );
  registry.register(
    createElgatoPlugin(
      configuredElgatoTransport,
      supportsRgb: elgatoRgb,
      numberOfLights: elgatoLights,
      transportResolver: (config) {
        final host = config['host']?.toString().trim() ?? '';
        if (host.isEmpty) return configuredElgatoTransport;
        return ElgatoTransport(
          ElgatoHttpTransport(
            host: host,
            port: _port(config['port'], elgatoPort),
          ).request,
        );
      },
    ),
  );
  final kasaSettings = await dataService.loadPluginSettings('tplink-kasa');
  final kasaHost = kasaSettings['host']?.toString().trim();
  final kasaTransport = kasaHost?.isNotEmpty == true
      ? KasaTcpTransport(
          host: kasaHost!,
          port: _port(kasaSettings['port'], 9999),
        )
      : null;
  final configuredKasaTransport = KasaTransport(
    kasaTransport?.request ?? _unconfiguredKasa,
  );
  registry.register(
    createKasaPlugin(
      configuredKasaTransport,
      transportResolver: (config) {
        final host = config['host']?.toString().trim() ?? '';
        if (host.isEmpty) return configuredKasaTransport;
        return KasaTransport(
          KasaTcpTransport(
            host: host,
            port: _port(config['port'], 9999),
          ).request,
        );
      },
    ),
  );
  final lifxSettings = await dataService.loadPluginSettings('lifx');
  final lifxHost = lifxSettings['host']?.toString().trim();
  final lifxTransport = lifxHost?.isNotEmpty == true
      ? LifxUdpTransport(
          host: lifxHost!,
          port: _port(lifxSettings['port'], 56700),
          target: parseLifxTarget(lifxSettings['target']?.toString()),
        )
      : null;
  final configuredLifxTransport = lifxTransport ?? _unconfiguredLifxTransport;
  registry.register(
    createLifxPlugin(
      configuredLifxTransport,
      transportResolver: (config) {
        final host = config['host']?.toString().trim() ?? '';
        if (host.isEmpty) return configuredLifxTransport;
        return LifxUdpTransport(
          host: host,
          port: _port(config['port'], 56700),
          target: parseLifxTarget(config['target']?.toString()),
        );
      },
    ),
  );
  final wyzeSettings = await dataService.loadPluginSettings('wyze');
  final wyzeTransport = WyzeHttpTransport(
    keyId: wyzeSettings['keyId']?.toString() ?? '',
    apiKey: wyzeSettings['apiKey']?.toString() ?? '',
    accessToken: wyzeSettings['accessToken']?.toString(),
    refreshToken: wyzeSettings['refreshToken']?.toString(),
    onTokens: (tokens) async {
      final current = await dataService.loadPluginSettings('wyze');
      await dataService.savePluginSettings('wyze', {
        ...current,
        'accessToken': tokens.accessToken,
        'refreshToken': tokens.refreshToken,
      });
    },
  );
  registry.register(createWyzePlugin(wyzeTransport));
  registry.register(dashboardPlugin);
  registry.register(createInputPlugin(startEvents: true));
  registry.register(createStreamPlansPlugin(registry: registry));
  registry.register(
    createIotPlugin(
      resolver: createConfiguredIotResolver(
        registry: registry,
        dataService: dataService,
      ),
    ),
  );
  final disabled = appSettings['disabledPlugins'];
  if (disabled is List) {
    for (final pluginId in disabled.whereType<String>()) {
      registry.setPluginEnabled(pluginId, false);
    }
  }
  await registry.initialize(
    DartPluginHostContext(
      services: {'dataService': dataService, 'eventHub': ?eventHub},
    ),
  );
  await registry.start();
  return registry;
}

Future<List<String>> _loadRemoteButtonNames(
  ShowRunnerDataService dataService,
) async {
  final names = <String>{};
  for (final fileName in await dataService.listUserFiles('profiles')) {
    try {
      final profile = await ProfileRepository(
        File('${dataService.userDirectory.path}/profiles/$fileName'),
      ).load();
      if (profile == null) continue;
      for (final trigger in profile.triggers) {
        _addRemoteButtonName(names, trigger);
      }
    } on Object {
      // A malformed profile should not make the remote button API unavailable.
    }
  }
  return names.toList(growable: false);
}

Future<AutomationData?> _loadAutomationResource(
  ShowRunnerDataService dataService,
  String automationId,
) async {
  final normalized = automationId.trim();
  if (normalized.isEmpty ||
      normalized.contains('/') ||
      normalized.contains('\\')) {
    return null;
  }
  final fileName = normalized.endsWith('.yaml')
      ? normalized
      : '$normalized.yaml';
  return AutomationRepository(
    File('${dataService.userDirectory.path}/automations/$fileName'),
  ).load();
}

void _addRemoteButtonName(Set<String> names, Object? trigger) {
  if (trigger is! Map ||
      trigger['plugin']?.toString() != 'remote' ||
      trigger['trigger']?.toString() != 'button') {
    return;
  }
  final config = trigger['config'];
  final name = config is Map ? config['name']?.toString().trim() : null;
  if (name?.isNotEmpty == true) names.add(name!);
}

void _registerTwitchStreamPlanComponent({
  required TwitchTransport transport,
  String? broadcasterId,
}) {
  streamPlanRuntime.registerComponentType(
    DartStreamPlanComponent(
      id: 'twitch-stream-info',
      onActivate: (segmentId, rawConfig) async {
        final config = rawConfig is Map
            ? Map<String, dynamic>.from(rawConfig)
            : const <String, dynamic>{};
        final category = config['categoryId'] ?? config['category'];
        final categoryId = category is Map ? category['id'] : category;
        final tags = config['tags'] is List ? config['tags'] : null;
        final body = <String, dynamic>{
          'title': ?config['title'],
          'game_id': ?categoryId,
          'tags': ?tags,
        };
        if (body.isEmpty) return;
        await transport.request('PATCH', '/helix/channels', {
          'broadcaster_id':
              config['broadcasterId']?.toString() ?? broadcasterId ?? '',
        }, body);
      },
    ),
  );
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

Future<RuntimeMap> _unconfiguredAitum(String request, RuntimeMap data) =>
    Future<RuntimeMap>.error(
      StateError('Aitum requires a configured OBS connection.'),
    );

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

Future<RuntimeMap> _unconfiguredGovee(
  String method,
  String path,
  RuntimeMap query,
  dynamic body,
) => Future<RuntimeMap>.error(StateError('Govee transport is not configured.'));

Future<RuntimeMap> _unconfiguredPhilipsHue(
  String method,
  String path,
  RuntimeMap query,
  dynamic body,
) => Future<RuntimeMap>.error(
  StateError('Philips Hue transport is not configured.'),
);

Future<RuntimeMap> _unconfiguredTwinkly(
  String ip,
  String method,
  String path,
  RuntimeMap query,
  dynamic body,
) => Future<RuntimeMap>.error(
  StateError('Twinkly transport is not configured.'),
);

Future<RuntimeMap> _unconfiguredBluesky(
  String identifier,
  String appPassword,
  String text,
) => Future<RuntimeMap>.error(
  StateError('Bluesky transport is not configured.'),
);

Future<RuntimeMap> _unconfiguredElgato(
  String method,
  String path,
  dynamic body,
) =>
    Future<RuntimeMap>.error(StateError('Elgato transport is not configured.'));

Future<RuntimeMap> _unconfiguredKasa(RuntimeMap request) =>
    Future<RuntimeMap>.error(
      StateError('TP-Link Kasa transport is not configured.'),
    );

final LifxTransport _unconfiguredLifxTransport = CallbackLifxTransport(
  getStateCallback: () =>
      Future<RuntimeMap>.error(StateError('LIFX transport is not configured.')),
  setPowerCallback: (on, transitionMilliseconds) =>
      Future<RuntimeMap>.error(StateError('LIFX transport is not configured.')),
  setColorCallback: (color, transitionMilliseconds) =>
      Future<RuntimeMap>.error(StateError('LIFX transport is not configured.')),
);

final WyzeTransport _unconfiguredWyzeTransport = CallbackWyzeTransport(
  loginCallback: (email, password) =>
      Future<WyzeToken>.error(StateError('Wyze transport is not configured.')),
  getDevicesCallback: () => Future<List<RuntimeMap>>.error(
    StateError('Wyze transport is not configured.'),
  ),
  getDeviceStateCallback: (mac, model) =>
      Future<RuntimeMap>.error(StateError('Wyze transport is not configured.')),
  setLightStateCallback: (mac, model, properties) =>
      Future<RuntimeMap>.error(StateError('Wyze transport is not configured.')),
  setPlugStateCallback: (mac, model, on) =>
      Future<RuntimeMap>.error(StateError('Wyze transport is not configured.')),
);

Future<List<RuntimeMap>> _unconfiguredVoiceModVoices() =>
    Future.error(StateError('VoiceMod transport is not configured.'));

Future<RuntimeMap> _unconfiguredVoiceMod(String voiceId) =>
    Future.error(StateError('VoiceMod transport is not configured.'));

Duration _positiveDuration(Object? value, Duration fallback) {
  final seconds = value is num ? value.toDouble() : double.tryParse('$value');
  if (seconds == null || !seconds.isFinite || seconds <= 0) return fallback;
  return Duration(milliseconds: (seconds * 1000).round());
}

int _port(Object? value, int fallback) {
  final port = value is num ? value.toInt() : int.tryParse('$value');
  return port != null && port >= 1 && port <= 65535 ? port : fallback;
}

int _positiveInt(Object? value, int fallback) {
  final number = value is num ? value.toInt() : int.tryParse('$value');
  return number != null && number > 0 ? number : fallback;
}

double _percentage(Object? value, double fallback) {
  final number = value is num ? value.toDouble() : double.tryParse('$value');
  if (number == null || !number.isFinite) return fallback;
  return number.clamp(0, 100).toDouble();
}
