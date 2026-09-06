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
  registry.register(createObsPlugin(CallbackObsTransport(_unconfiguredObs)));
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
  registry.register(createModerationPlugin(moderationService));
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
  registry.register(createWyzePlugin(_unconfiguredWyzeTransport));
  registry.register(dashboardPlugin);
  registry.register(createInputPlugin());
  registry.register(
    createStreamPlansPlugin(registry: registry, queueManager: queueManager),
  );
  return registry;
}
