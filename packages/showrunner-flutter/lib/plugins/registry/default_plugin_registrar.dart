part of 'plugin_bootstrap.dart';

DartPluginRegistry buildDefaultPluginRegistry({
  DartPluginEventHub? eventHub,
  TtsSpeechService? ttsService,
  SoundOutputRegistry? soundOutputs,
  ViewerDataRepository? viewerDataRepository,
  DartAutomationQueueManager? queueManager,
  GraphExecutionEngine? executionEngine,
  ShowRunnerAutomationRunner? runAutomation,
  ShowRunnerProfileActivation? activateProfile,
}) {
  final variablesRepository =
      viewerDataRepository ?? InMemoryViewerDataRepository();
  final registry = DartPluginRegistry();
  _registerHeartRatePlugin(registry, eventHub: eventHub);
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
  registry.register(
    createBlueskyPlugin(BlueskyTransport(_unconfiguredBluesky)),
  );
  registry.register(createDonorDrivePlugin(null, eventHub: eventHub));
  registry.register(createRemotePlugin(eventHub: eventHub));
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
  registry.register(createMinecraftPlugin());
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
  final spellcastHub = eventHub ?? DartPluginEventHub();
  registry.register(createSpellcastPlugin(eventHub: spellcastHub));
  registry.registerUi('spellcast', createSpellcastPluginUi(spellcastHub));
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
  registry.register(
    createWyzePlugin(_unconfiguredWyzeTransport),
    onStop: _unconfiguredWyzeTransport.close,
  );
  registry.register(dashboardPlugin);
  registry.register(createInputPlugin());
  registry.register(
    createStreamPlansPlugin(
      registry: registry,
      queueManager: queueManager,
      executionEngine: executionEngine,
    ),
  );
  _registerCommonPluginUis(registry);
  return registry;
}

void _registerCommonPluginUis(DartPluginRegistry registry) {
  final factories = <String, DartPluginUiContribution Function()>{
    'obs': createObsPluginUi,
    'youtube': createYouTubePluginUi,
    'twitch': createTwitchPluginUi,
    'discord': createDiscordPluginUi,
    'bluesky': createBlueskyPluginUi,
    'remote': createRemotePluginUi,
    'sound': createSoundPluginUi,
    'minecraft': createMinecraftPluginUi,
    'overlays': createOverlaysPluginUi,
    'iot': createIotPluginUi,
    'wyze': createWyzePluginUi,
    'dashboards': createDashboardsPluginUi,
    'input': createInputPluginUi,
    'stream-plans': createStreamPlansPluginUi,
  };
  for (final entry in factories.entries) {
    if (registry.findPlugin(entry.key) != null &&
        registry.uiFor(entry.key) == null) {
      registry.registerUi(entry.key, entry.value());
    }
  }

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
