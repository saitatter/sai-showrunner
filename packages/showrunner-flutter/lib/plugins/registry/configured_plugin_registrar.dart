import 'dart:async';
import 'dart:io';
import '../../features/chat/command_manager.dart';
import '../../graph/runtime/graph_execution_engine.dart';
import '../../persistence/viewer_data_repository.dart';
import '../../runtime/automation_queue_manager.dart';
import '../../services/plugin_event_hub.dart';
import '../../services/showrunner_data_service.dart';
import '../../services/structured_logger.dart';
import '../bluesky/bootstrap.dart';
import '../chat_commands/bootstrap.dart';
import '../dashboards/bootstrap.dart';
import '../discord/bootstrap.dart';
import '../donordrive/bootstrap.dart';
import '../elgato/bootstrap.dart';
import '../govee/bootstrap.dart';
import '../heartrate/bootstrap.dart';
import '../http/bootstrap.dart';
import '../input/bootstrap.dart';
import '../iot/bootstrap.dart';
import '../lifx/bootstrap.dart';
import '../minecraft/bootstrap.dart';
import '../moderation/bootstrap.dart';
import '../obs/bootstrap.dart';
import '../os/bootstrap.dart';
import '../overlays/bootstrap.dart';
import '../overlays/overlay_presence.dart';
import '../philips_hue/bootstrap.dart';
import '../random/bootstrap.dart';
import '../remote/bootstrap.dart';
import '../showrunner/bootstrap.dart';
import '../showrunner/manifest.dart';
import '../sound/bootstrap.dart';
import '../sound/output.dart';
import '../sound/tts_runtime.dart';
import '../spellcast/bootstrap.dart';
import '../stream_plans/bootstrap.dart';
import '../stream_plans/manifest.dart';
import '../time/bootstrap.dart';
import '../tplink_kasa/bootstrap.dart';
import '../twinkly/bootstrap.dart';
import '../twitch/bootstrap.dart';
import '../variables/bootstrap.dart';
import '../variables/runtime.dart';
import '../voicemod/bootstrap.dart';
import '../wyze/bootstrap.dart';
import '../youtube/bootstrap.dart';
import 'first_party_plugin_ui.dart';
import 'plugin_host_context.dart';
import 'plugin_registry.dart';

Future<DartPluginRegistry> createConfiguredPluginRegistry(
  ShowRunnerDataService dataService, {
  DartPluginEventHub? eventHub,
  Future<ChatCommandManager>? chatCommands,
  TtsSpeechService? ttsService,
  SoundOutputRegistry? soundOutputs,
  ViewerDataRepository? viewerDataRepository,
  DartAutomationQueueManager? queueManager,
  GraphExecutionEngine? executionEngine,
  ShowRunnerAutomationRunner? runAutomation,
  ShowRunnerProfileActivation? activateProfile,
  DartStreamPlanRuntime? streamPlans,
  DartVariableRuntime? variableRuntime,
  int? httpPortOverride,
  bool startRuntime = true,
  void Function(OverlayPresenceReader reader)? onOverlayPresenceReaderCreated,
}) async {
  final variablesRepository =
      viewerDataRepository ??
      FileViewerDataRepository(
        Directory('${dataService.userDirectory.path}/viewer-data'),
      );
  final interfaceSettings = await dataService.loadPluginSettings(
    'showrunner-flutter',
  );
  final showRunnerSettings = await dataService.loadPluginSettings('ShowRunner');
  final appSettings = <String, dynamic>{
    ...interfaceSettings,
    ...showRunnerSettings,
  };
  final httpEndpointService = createPluginHttpEndpoint(
    settings: appSettings,
    portOverride: httpPortOverride,
  );
  final registry = createFirstPartyPluginRegistry();
  final activeStreamPlans = streamPlans ?? DartStreamPlanRuntime();
  try {
    registerConfiguredChatCommands(
      registry,
      eventHub: eventHub,
      chatCommands: chatCommands,
    );
    registerHeartRatePlugin(
      registry,
      dataService: dataService,
      eventHub: eventHub,
    );
    final dashboardHost = createPluginDashboardHost(
      dataService: dataService,
      registry: registry,
      eventHub: eventHub,
    );
    registerConfiguredShowRunner(
      registry,
      dataService: dataService,
      queueManager: queueManager,
      runAutomation: runAutomation,
      activateProfile: activateProfile,
    );
    registerConfiguredObsPack(
      registry,
      dataService: dataService,
      eventHub: eventHub,
    );
    await registerConfiguredYouTube(
      registry,
      dataService: dataService,
      eventHub: eventHub,
    );
    await registerConfiguredTwitch(
      registry,
      dataService: dataService,
      eventHub: eventHub,
      activeStreamPlans: activeStreamPlans,
    );
    registerConfiguredModeration(registry, dataService: dataService);
    await registerConfiguredDiscord(registry, dataService: dataService);
    await registerConfiguredBluesky(registry, dataService: dataService);
    await registerConfiguredDonorDrive(
      registry,
      dataService: dataService,
      eventHub: eventHub,
    );
    await registerConfiguredRemote(
      registry,
      dataService: dataService,
      eventHub: eventHub,
    );
    await registerConfiguredVoiceMod(registry, dataService: dataService);
    final configuredSoundOutputs = await registerConfiguredSound(
      registry,
      dataService: dataService,
      ttsService: ttsService,
      soundOutputs: soundOutputs,
    );
    await registerConfiguredMinecraft(registry, dataService: dataService);
    registerConfiguredHttp(
      registry,
      eventHub: eventHub,
      httpEndpointService: httpEndpointService,
    );
    final configuredVariableRuntime =
        variableRuntime ??
        createPluginVariableRuntime(
          dataService: dataService,
          registry: registry,
        );
    registerConfiguredTime(
      registry,
      configuredVariableRuntime: configuredVariableRuntime,
    );
    registerDefaultOs(registry);
    registerDefaultRandom(registry, eventHub: eventHub);
    registerConfiguredVariables(
      registry,
      eventHub: eventHub,
      variablesRepository: variablesRepository,
      variableRuntime: variableRuntime,
      configuredVariableRuntime: configuredVariableRuntime,
    );
    await registerConfiguredOverlays(
      registry,
      dataService: dataService,
      eventHub: eventHub,
      variablesRepository: variablesRepository,
      httpEndpointService: httpEndpointService,
      configuredSoundOutputs: configuredSoundOutputs,
      onOverlayPresenceReaderCreated: onOverlayPresenceReaderCreated,
    );
    registerConfiguredSpellcast(registry, eventHub: eventHub);
    await registerConfiguredGovee(registry, dataService: dataService);
    await registerConfiguredPhilipsHue(registry, dataService: dataService);
    registerConfiguredTwinkly(registry);
    await registerConfiguredElgato(registry, dataService: dataService);
    await registerConfiguredKasa(registry, dataService: dataService);
    await registerConfiguredLifx(registry, dataService: dataService);
    await registerConfiguredWyze(registry, dataService: dataService);
    registerConfiguredDashboards(registry, dashboardHost: dashboardHost);
    registerConfiguredInput(registry);
    registerConfiguredStreamPlans(
      registry,
      queueManager: queueManager,
      executionEngine: executionEngine,
      activeStreamPlans: activeStreamPlans,
      streamPlans: streamPlans,
    );
    registerConfiguredIot(registry, dataService: dataService);
    registerCommonPluginUis(registry, activeStreamPlans);
    final disabled = appSettings['disabledPlugins'];
    if (disabled is List) {
      for (final pluginId in disabled.whereType<String>()) {
        registry.setPluginEnabledId(PluginId(pluginId), false);
      }
    }
    if (startRuntime) {
      await registry.initialize(
        DartPluginHostContext(
          services: {'dataService': dataService, 'eventHub': ?eventHub},
        ),
      );
      await registry.start();
    }
    return registry;
  } catch (error, stack) {
    try {
      await registry.close();
    } catch (cleanupError, cleanupStack) {
      ShowRunnerLogger.instance.error(
        'lifecycle',
        'Registry construction/startup cleanup failed',
        error: cleanupError,
        stackTrace: cleanupStack,
      );
    }
    Error.throwWithStackTrace(error, stack);
  }
}
