part of 'plugin_bootstrap.dart';

DartPluginRegistry buildDefaultPluginRegistry({
  DartPluginEventHub? eventHub,
  TtsSpeechService? ttsService,
  SoundOutputRegistry? soundOutputs,
  ViewerDataRepository? viewerDataRepository,
  DartAutomationQueueManager? queueManager,
  ShowRunnerAutomationRunner? runAutomation,
  ShowRunnerProfileActivation? activateProfile,
}) {
  final variablesRepository =
      viewerDataRepository ?? InMemoryViewerDataRepository();
  final registry = DartPluginRegistry();
  registry.register(
    createShowRunnerPlugin(
      queueManager: queueManager,
      runAutomation: runAutomation,
      activateProfile: activateProfile,
    ),
  );
  final obsTransport = CallbackObsTransport(_unconfiguredObs);
  registry.register(
    createObsPlugin(obsTransport),
    onHealthCheck: () async {
      await obsTransport.call('GetVersion', {});
      return true;
    },
  );
  registry.registerUi('obs', createObsPluginUi());
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
  registry.registerUi('youtube', createYouTubePluginUi());
  registry.register(
    createTwitchPlugin(
      TwitchTransport(_unconfiguredTwitch),
      eventHub: eventHub,
    ),
  );
  registry.registerUi('twitch', createTwitchPluginUi());
  _registerTwitchStreamPlanComponent(
    transport: TwitchTransport(_unconfiguredTwitch),
  );
  final moderationService = ModerationService(
    dataService: ShowRunnerDataService(Directory.systemTemp),
  );
  registry.register(
    createModerationPlugin(moderationService),
    onHealthCheck: () async =>
        (await moderationService.checkHealth()).health == 'healthy',
    onStop: moderationService.dispose,
  );
  registry.registerUi(
    'moderation',
    createModerationPluginUi(moderationService),
  );
  registry.register(createDiscordPlugin());
  registry.registerUi('discord', createDiscordPluginUi());
  registry.register(
    createBlueskyPlugin(BlueskyTransport(_unconfiguredBluesky)),
  );
  registry.registerUi('bluesky', createBlueskyPluginUi());
  registry.register(createDonorDrivePlugin(null, eventHub: eventHub));
  registry.register(createRemotePlugin(eventHub: eventHub));
  registry.registerUi('remote', createRemotePluginUi());
  final voiceModTransport = CallbackVoiceModTransport(
    getVoicesCallback: _unconfiguredVoiceModVoices,
    selectVoiceCallback: _unconfiguredVoiceMod,
  );
  registry.register(
    createVoiceModPlugin(voiceModTransport),
    onStop: voiceModTransport.close,
  );
  registry.register(
    createSoundPlugin(ttsService: ttsService, soundOutputs: soundOutputs),
  );
  registry.registerUi('sound', createSoundPluginUi());
  registry.register(createMinecraftPlugin());
  registry.registerUi('minecraft', createMinecraftPluginUi());
  registry.register(createHttpPlugin(eventHub: eventHub));
  registry.register(createTimePlugin());
  registry.register(createOsPlugin());
  registry.register(createRandomPlugin(eventHub: eventHub));
  registry.register(
    createVariablesPlugin(
      viewerDataRepository: variablesRepository,
      eventHub: eventHub,
    ),
  );
  registry.registerUi('variables', createVariablesPluginUi());
  registry.register(createOverlaysPlugin(eventHub: eventHub));
  registry.registerUi('overlays', createOverlaysPluginUi());
  final spellcastHub = eventHub ?? DartPluginEventHub();
  registry.register(createSpellcastPlugin(eventHub: spellcastHub));
  registry.registerUi('spellcast', createSpellcastPluginUi(spellcastHub));
  registry.register(createIotPlugin());
  registry.registerUi('iot', createIotPluginUi());
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
  registry.register(
    createWyzePlugin(_unconfiguredWyzeTransport),
    onStop: _unconfiguredWyzeTransport.close,
  );
  registry.registerUi('wyze', createWyzePluginUi());
  registry.register(dashboardPlugin);
  registry.registerUi('dashboards', createDashboardsPluginUi());
  registry.register(createInputPlugin());
  registry.registerUi('input', createInputPluginUi());
  registry.register(
    createStreamPlansPlugin(registry: registry, queueManager: queueManager),
  );
  registry.registerUi('stream-plans', createStreamPlansPluginUi());
  _registerGenericPluginUis(registry);
  return registry;
}

void _registerGenericPluginUis(DartPluginRegistry registry) {
  for (final pluginId in const [
    'advss',
    'aitum',
    'donordrive',
    'elgato',
    'govee',
    'http',
    'lifx',
    'os',
    'philips-hue',
    'random',
    'time',
    'tplink-kasa',
    'twinkly',
    'voicemod',
  ]) {
    registry.registerUi(pluginId, createGenericPluginUi(pluginId));
  }
}
