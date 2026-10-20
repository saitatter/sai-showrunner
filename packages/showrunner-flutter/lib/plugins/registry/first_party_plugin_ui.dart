import '../bluesky/ui/plugin_ui.dart';
import '../dashboards/ui/plugin_ui.dart';
import '../discord/ui/plugin_ui.dart';
import '../input/ui/plugin_ui.dart';
import '../iot/ui/plugin_ui.dart';
import '../minecraft/ui/plugin_ui.dart';
import '../obs/ui/plugin_ui.dart';
import '../overlays/ui/plugin_ui.dart';
import '../remote/ui/plugin_ui.dart';
import '../sound/ui/plugin_ui.dart';
import '../stream_plans/manifest.dart';
import '../stream_plans/ui/plugin_ui.dart';
import '../twitch/ui/plugin_ui.dart';
import '../wyze/ui/plugin_ui.dart';
import '../youtube/ui/plugin_ui.dart';
import 'flutter_plugin_ui_contract.dart';
import 'generic_plugin_ui.dart';
import 'plugin_registry.dart';

void registerCommonPluginUis(
  DartPluginRegistry registry,
  DartStreamPlanRuntime streamPlans,
) {
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
    'stream-plans': () => createStreamPlansPluginUi(runtime: streamPlans),
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
