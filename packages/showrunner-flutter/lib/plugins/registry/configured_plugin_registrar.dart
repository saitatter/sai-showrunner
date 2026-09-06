part of 'plugin_bootstrap.dart';

Future<DartPluginRegistry> createConfiguredPluginRegistry(
  ShowRunnerDataService dataService, {
  DartPluginEventHub? eventHub,
  TtsSpeechService? ttsService,
  SoundOutputRegistry? soundOutputs,
  ViewerDataRepository? viewerDataRepository,
  DartAutomationQueueManager? queueManager,
  ShowRunnerAutomationRunner? runAutomation,
  ShowRunnerProfileActivation? activateProfile,
  DartVariableRuntime? variableRuntime,
}) async {
  final variablesRepository =
      viewerDataRepository ??
      FileViewerDataRepository(
        Directory('${dataService.userDirectory.path}/viewer-data'),
      );
  final youtube = await dataService.loadPluginSettings('youtube');
  final twitch = await loadTwitchChannelSettings(dataService);
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
  final dashboardHost = eventHub == null
      ? null
      : RemoteDashboardHost(
          dataService: dataService,
          registry: registry,
          eventHub: eventHub,
          signaling: SatelliteSignalingController(dataService: dataService),
        );
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
  final discordWebhookRepository = ResourceRepository(
    Directory('${dataService.userDirectory.path}/discord/webhooks'),
    resourceType: 'DiscordWebhook',
    secretSettings: dataService.secretSettingsStore,
  );
  registry.register(
    createDiscordPlugin(
      webhookResolver: (id) async =>
          (await discordWebhookRepository.load(id))?.config,
    ),
  );
  registry.registerUi('discord', createDiscordPluginUi());
  final blueskySettings = await dataService.loadPluginSettings('bluesky');
  final blueskyIdentifier = blueskySettings['identifier']?.toString().trim();
  final blueskyPassword = blueskySettings['appPassword']?.toString().trim();
  final blueskyServiceUrl = blueskySettings['serviceUrl']?.toString().trim();
  final blueskyHttp = BlueskyHttpTransport(
    baseUrl: blueskyServiceUrl?.isNotEmpty == true
        ? blueskyServiceUrl!
        : 'https://bsky.social',
  );
  final blueskyAccountRepository = ResourceRepository(
    Directory('${dataService.userDirectory.path}/accounts/bluesky'),
    resourceType: 'BlueSkyAccount',
    secretSettings: dataService.secretSettingsStore,
  );
  registry.register(
    createBlueskyPlugin(
      BlueskyTransport(
        blueskyHttp.post,
        postWithSession: blueskyHttp.postWithSession,
      ),
      identifier: blueskyIdentifier,
      appPassword: blueskyPassword,
      accountResolver: (id) async =>
          (await blueskyAccountRepository.load(id))?.config,
    ),
  );
  registry.registerUi('bluesky', createBlueskyPluginUi());
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
  registry.registerUi('remote', createRemotePluginUi());
  final voiceModSettings = await dataService.loadPluginSettings('voicemod');
  final voiceModHost = voiceModSettings['host']?.toString().trim();
  final voiceModTransport = VoiceModWebSocketTransport(
    host: voiceModHost?.isNotEmpty == true ? voiceModHost! : '127.0.0.1',
    port: _port(voiceModSettings['port'], 59129),
  );
  final soundSettings = await dataService.loadPluginSettings('sound');
  final defaultOutput = soundSettings['defaultOutput']?.toString().trim();
  final splitterDirectory = Directory(
    '${dataService.userDirectory.path}/sound/splitters',
  );
  late final SoundOutputRegistry configuredSoundOutputs;
  Future<void> refreshSoundSplitters() async {
    final splitters = await ResourceRepository(splitterDirectory).list();
    for (final splitter in splitters) {
      configuredSoundOutputs.registerSplitterConfig(
        splitter.id,
        splitter.config,
      );
    }
  }

  configuredSoundOutputs =
      soundOutputs ??
      createDefaultSoundOutputRegistry(
        defaultOutputId: defaultOutput,
        refresh: refreshSoundSplitters,
      );
  if (soundOutputs != null && defaultOutput?.isNotEmpty == true) {
    configuredSoundOutputs.defaultOutputId = defaultOutput;
  }
  if (soundOutputs == null) {
    await refreshSoundSplitters();
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
  registry.registerUi('sound', createSoundPluginUi());
  final rconConnectionRepository = ResourceRepository(
    Directory('${dataService.userDirectory.path}/minecraft/connections'),
    resourceType: 'RCONConnection',
    secretSettings: dataService.secretSettingsStore,
  );
  registry.register(
    createMinecraftPlugin(
      connectionResolver: (id) async =>
          (await rconConnectionRepository.load(id))?.config,
    ),
  );
  registry.registerUi('minecraft', createMinecraftPluginUi());
  registry.register(
    createHttpPlugin(eventHub: eventHub, endpointService: httpEndpointService),
  );
  final configuredVariableRuntime =
      variableRuntime ??
      DartVariableRuntime(
        directory: Directory('${dataService.userDirectory.path}/variables'),
        onChanged: (id, value) =>
            registry.updateDynamicState('variables', id, value),
      );
  registry.register(
    createTimePlugin(variableRuntime: configuredVariableRuntime),
  );
  registry.register(createOsPlugin());
  registry.register(createRandomPlugin(eventHub: eventHub));
  registry.register(
    createVariablesPlugin(
      viewerDataRepository: variablesRepository,
      eventHub: eventHub,
      variableRuntime: configuredVariableRuntime,
    ),
  );
  registry.registerUi(
    'variables',
    createVariablesPluginUi(variableRuntime: configuredVariableRuntime),
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
  registry.registerUi('overlays', createOverlaysPluginUi());
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
  if (hueTransport != null) {
    try {
      await PhilipsHueResourceSynchronizer(
        lightDirectory: Directory(
          '${dataService.userDirectory.path}/iot/lights',
        ),
        plugDirectory: Directory('${dataService.userDirectory.path}/iot/plugs'),
        secretSettings: dataService.secretSettingsStore,
      ).sync(configuredHueTransport);
    } catch (_) {
      // Resource discovery is best effort; actions can still use manually
      // configured Hue resources when the bridge is temporarily offline.
    }
  }
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
  final wyzeSettings = await loadWyzeAccountSettings(dataService);
  final wyzeTransport = WyzeHttpTransport(
    keyId: wyzeSettings['keyId']?.toString() ?? '',
    apiKey: wyzeSettings['apiKey']?.toString() ?? '',
    accessToken: wyzeSettings['accessToken']?.toString(),
    refreshToken: wyzeSettings['refreshToken']?.toString(),
    onTokens: (tokens) async {
      await saveWyzeAccountTokens(
        dataService,
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
    },
  );
  registry.register(createWyzePlugin(wyzeTransport));
  registry.registerUi('wyze', createWyzePluginUi());
  registry.register(
    createDashboardPlugin(
      start: dashboardHost?.start,
      stop: dashboardHost?.stop,
    ),
  );
  registry.registerUi('dashboards', createDashboardsPluginUi());
  registry.register(createInputPlugin(startEvents: true));
  registry.registerUi('input', createInputPluginUi());
  registry.register(
    createStreamPlansPlugin(registry: registry, queueManager: queueManager),
  );
  registry.registerUi('stream-plans', createStreamPlansPluginUi());
  registry.register(
    createIotPlugin(
      resolver: createConfiguredIotResolver(
        registry: registry,
        dataService: dataService,
      ),
    ),
  );
  registry.registerUi('iot', createIotPluginUi());
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
