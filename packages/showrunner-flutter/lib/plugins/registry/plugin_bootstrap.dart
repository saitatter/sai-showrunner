import 'dart:io';

import 'dart:async';

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
import '../bluesky/manifest.dart';
import '../donordrive/manifest.dart';
import '../aitum/manifest.dart';
import '../advss/manifest.dart';
import '../remote/manifest.dart';
import '../voicemod/manifest.dart';
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
    createAitumPlugin(CallbackObsTransport(_unconfiguredAitum)),
  );
  registry.register(
    createAdvssPlugin(
      CallbackObsTransport(_unconfiguredAitum),
      eventHub: eventHub,
    ),
  );
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
    createBlueskyPlugin(BlueskyTransport(_unconfiguredBluesky)),
  );
  registry.register(createDonorDrivePlugin(null));
  registry.register(createRemotePlugin(eventHub: eventHub));
  registry.register(
    createVoiceModPlugin(
      CallbackVoiceModTransport(
        getVoicesCallback: _unconfiguredVoiceModVoices,
        selectVoiceCallback: _unconfiguredVoiceMod,
      ),
    ),
  );
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
  registry.register(createGoveePlugin(GoveeTransport(_unconfiguredGovee)));
  registry.register(
    createPhilipsHuePlugin(HueTransport(_unconfiguredPhilipsHue)),
  );
  registry.register(
    createTwinklyPlugin(TwinklyTransport(_unconfiguredTwinkly)),
  );
  registry.register(createElgatoPlugin(ElgatoTransport(_unconfiguredElgato)));
  registry.register(createKasaPlugin(KasaTransport(_unconfiguredKasa)));
  registry.register(createLifxPlugin(_unconfiguredLifxTransport));
  registry.register(createWyzePlugin(_unconfiguredWyzeTransport));
  registry.register(dashboardPlugin);
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
  final obsTransport = host != null && port != null
      ? ObsWebSocketTransport(
          host: host,
          port: port,
          password: obs['password'] as String?,
          eventHub: eventHub,
        )
      : CallbackObsTransport(_unconfiguredObs);
  registry.register(createObsPlugin(obsTransport));
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
  if (donorDriveRuntime != null) unawaited(donorDriveRuntime.start());
  final remoteSettings = await dataService.loadPluginSettings('remote');
  final remoteEnabled = remoteSettings['enabled'] == true;
  final remoteHost = remoteSettings['host']?.toString().trim();
  final remotePort = _port(remoteSettings['port'], 8390);
  final remoteRuntime = remoteEnabled && eventHub != null
      ? RemoteButtonRuntime(
          eventHub: eventHub,
          host: remoteHost?.isNotEmpty == true ? remoteHost! : '127.0.0.1',
          port: remotePort,
        )
      : null;
  registry.register(
    createRemotePlugin(eventHub: eventHub, runtime: remoteRuntime),
  );
  if (remoteRuntime != null) unawaited(remoteRuntime.start());
  final voiceModSettings = await dataService.loadPluginSettings('voicemod');
  final voiceModHost = voiceModSettings['host']?.toString().trim();
  final voiceModTransport = VoiceModWebSocketTransport(
    host: voiceModHost?.isNotEmpty == true ? voiceModHost! : '127.0.0.1',
    port: _port(voiceModSettings['port'], 59129),
  );
  registry.register(createVoiceModPlugin(voiceModTransport));
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
  registry.register(
    createPhilipsHuePlugin(
      HueTransport(hueTransport?.request ?? _unconfiguredPhilipsHue),
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
  registry.register(
    createElgatoPlugin(
      ElgatoTransport(elgatoTransport?.request ?? _unconfiguredElgato),
      supportsRgb: elgatoRgb,
      numberOfLights: elgatoLights,
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
  registry.register(
    createKasaPlugin(
      KasaTransport(kasaTransport?.request ?? _unconfiguredKasa),
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
  registry.register(
    createLifxPlugin(lifxTransport ?? _unconfiguredLifxTransport),
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
  registry.register(createInputPlugin());
  registry.register(createStreamPlansPlugin());
  registry.register(
    createIotPlugin(
      resolver: _configuredIotResolver(
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
  return registry;
}

IotResourceActionResolver _configuredIotResolver({
  required DartPluginRegistry registry,
  required ShowRunnerDataService dataService,
}) => (resourceType, resourceId, actionConfig, context) async {
  final directory = resourceType == 'Light' ? 'iot/lights' : 'iot/plugs';
  final resource = await ResourceRepository(
    Directory('${dataService.userDirectory.path}/$directory'),
  ).load(resourceId);
  if (resource == null) {
    throw StateError('$resourceType resource "$resourceId" was not found.');
  }

  final device = <String, dynamic>{...resource.config, ...actionConfig};
  final provider = device['provider']?.toString().trim().toLowerCase() ?? '';
  if (provider.isEmpty) {
    throw StateError('$resourceType resource "$resourceId" has no provider.');
  }
  final providerId = device['providerId']?.toString().trim() ?? '';
  if (providerId.isEmpty) {
    throw StateError(
      '$resourceType resource "$resourceId" has no provider ID.',
    );
  }

  final hasColor = device['color']?.toString().trim().isNotEmpty == true;
  final hasPower = device.containsKey('on') || device.containsKey('state');
  final state = _iotState(device['on'] ?? device['state'] ?? 'on');
  final color = device['color'] ?? device['lightColor'];
  final transition = device['transition'] ?? 0.5;

  switch (provider) {
    case 'govee':
      if (resourceType == 'Plug' || !hasColor) {
        return registry.invokeAction('govee', 'setPower', {
          'device': providerId,
          'model': _requiredDeviceField(device, 'model', resourceId),
          'state': state,
        }, context: context);
      }
      if (hasPower) {
        await registry.invokeAction('govee', 'setPower', {
          'device': providerId,
          'model': _requiredDeviceField(device, 'model', resourceId),
          'state': state,
        }, context: context);
      }
      return registry.invokeAction('govee', 'setColor', {
        'device': providerId,
        'model': _requiredDeviceField(device, 'model', resourceId),
        'color': color,
      }, context: context);
    case 'philips-hue':
      if (resourceType != 'Light') {
        throw UnsupportedError('Philips Hue plug resources are not supported.');
      }
      return registry.invokeAction('philips-hue', 'setLightState', {
        'lightId': providerId,
        'resourceType': device['resourceType'] ?? 'light',
        'state': state,
        'color': color,
        'transition': transition,
      }, context: context);
    case 'twinkly':
      if (resourceType != 'Light') {
        throw UnsupportedError('Twinkly plug resources are not supported.');
      }
      final ip = _deviceHost(device, resourceId);
      if (hasPower && !state) {
        return registry.invokeAction('twinkly', 'turnOff', {
          'ip': ip,
        }, context: context);
      }
      if (!hasColor) {
        throw UnsupportedError(
          'Twinkly can only turn on through a color or movie.',
        );
      }
      return registry.invokeAction('twinkly', 'setColor', {
        'ip': ip,
        'color': color,
      }, context: context);
    case 'elgato':
      if (resourceType != 'Light') {
        throw UnsupportedError('Elgato plug resources are not supported.');
      }
      return registry.invokeAction('elgato', 'setLightState', {
        'state': state,
        'color': color,
        'numberOfLights': _positiveDeviceInt(device['numberOfLights'], 1),
      }, context: context);
    case 'tplink-kasa':
      return registry.invokeAction(
        'tplink-kasa',
        resourceType == 'Plug' ? 'setPlugState' : 'setLightState',
        {
          'state': state,
          if (resourceType == 'Light') ...{
            'color': color,
            'transition': transition,
          },
        },
        context: context,
      );
    case 'lifx':
      if (resourceType != 'Light') {
        throw UnsupportedError('LIFX plug resources are not supported.');
      }
      if (hasPower && !hasColor) {
        return registry.invokeAction('lifx', 'setPower', {
          'state': state,
          'transition': transition,
        }, context: context);
      }
      return registry.invokeAction('lifx', 'setLightState', {
        'state': state,
        'color': color,
        'transition': transition,
      }, context: context);
    case 'wyze':
      return registry.invokeAction(
        'wyze',
        resourceType == 'Plug' ? 'setPlugState' : 'setLightState',
        {
          'device': providerId,
          'model': _requiredDeviceField(device, 'model', resourceId),
          'state': state,
          if (resourceType == 'Light') 'color': color,
        },
        context: context,
      );
    default:
      throw UnsupportedError(
        'IoT provider "$provider" has no Flutter resource dispatcher.',
      );
  }
};

String _requiredDeviceField(
  Map<String, dynamic> config,
  String field,
  String resourceId,
) {
  final value = config[field]?.toString().trim() ?? '';
  if (value.isEmpty) {
    throw StateError('IoT resource "$resourceId" has no $field.');
  }
  return value;
}

String _deviceHost(Map<String, dynamic> config, String resourceId) {
  final host = config['ip']?.toString().trim().isNotEmpty == true
      ? config['ip'].toString().trim()
      : config['host']?.toString().trim() ?? '';
  if (host.isEmpty) throw StateError('IoT resource "$resourceId" has no IP.');
  return host;
}

bool _iotState(Object? value) {
  if (value is bool) return value;
  final text = value?.toString().trim().toLowerCase();
  return text != 'false' && text != 'off' && text != '0';
}

int _positiveDeviceInt(Object? value, int fallback) {
  final number = value is num ? value.toInt() : int.tryParse('$value');
  return number != null && number > 0 ? number : fallback;
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
