import '../../graph/runtime/graph_execution_engine.dart';
import '../../persistence/viewer_data_repository.dart';
import '../../runtime/automation_queue_manager.dart';
import '../../services/plugin_event_hub.dart';
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
import '../voicemod/bootstrap.dart';
import '../wyze/bootstrap.dart';
import '../youtube/bootstrap.dart';
import 'first_party_plugin_ui.dart';
import 'plugin_registry.dart';

DartPluginRegistry buildDefaultPluginRegistry({
  DartPluginEventHub? eventHub,
  TtsSpeechService? ttsService,
  SoundOutputRegistry? soundOutputs,
  ViewerDataRepository? viewerDataRepository,
  DartAutomationQueueManager? queueManager,
  GraphExecutionEngine? executionEngine,
  ShowRunnerAutomationRunner? runAutomation,
  ShowRunnerProfileActivation? activateProfile,
  DartStreamPlanRuntime? streamPlans,
}) {
  final variablesRepository =
      viewerDataRepository ?? InMemoryViewerDataRepository();
  final registry = DartPluginRegistry();
  final activeStreamPlans = streamPlans ?? DartStreamPlanRuntime();
  registerDefaultChatCommands(registry, eventHub: eventHub);
  registerHeartRatePlugin(registry, eventHub: eventHub);
  registerDefaultShowRunner(
    registry,
    queueManager: queueManager,
    runAutomation: runAutomation,
    activateProfile: activateProfile,
  );
  registerDefaultObsPack(registry, eventHub: eventHub);
  registerDefaultYouTube(registry, eventHub: eventHub);
  registerDefaultTwitch(
    registry,
    eventHub: eventHub,
    activeStreamPlans: activeStreamPlans,
  );
  registerDefaultModeration(registry);
  registerDefaultDiscord(registry);
  registerDefaultBluesky(registry);
  registerDefaultDonorDrive(registry, eventHub: eventHub);
  registerDefaultRemote(registry, eventHub: eventHub);
  registerDefaultVoiceMod(registry);
  registerDefaultSound(
    registry,
    ttsService: ttsService,
    soundOutputs: soundOutputs,
  );
  registerDefaultMinecraft(registry);
  registerDefaultHttp(registry, eventHub: eventHub);
  registerDefaultTime(registry);
  registerDefaultOs(registry);
  registerDefaultRandom(registry, eventHub: eventHub);
  registerDefaultVariables(
    registry,
    eventHub: eventHub,
    variablesRepository: variablesRepository,
  );
  registerDefaultOverlays(registry, eventHub: eventHub);
  registerDefaultSpellcast(registry, eventHub: eventHub);
  registerDefaultIot(registry);
  registerDefaultGovee(registry);
  registerDefaultPhilipsHue(registry);
  registerDefaultTwinkly(registry);
  registerDefaultElgato(registry);
  registerDefaultKasa(registry);
  registerDefaultLifx(registry);
  registerDefaultWyze(registry);
  registerDefaultDashboards(registry);
  registerDefaultInput(registry);
  registerDefaultStreamPlans(
    registry,
    queueManager: queueManager,
    executionEngine: executionEngine,
    activeStreamPlans: activeStreamPlans,
    streamPlans: streamPlans,
  );
  registerCommonPluginUis(registry, activeStreamPlans);
  return registry;
}
