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
import '../remote/dashboard_host.dart';
import '../remote/satellite.dart';
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
import '../philips_hue/resource_sync.dart';
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
part 'configured_plugin_registrar.dart';

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
  Future<void> updateStreamInfo(String segmentId, dynamic rawConfig) async {
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
  }

  streamPlanRuntime.registerComponentType(
    DartStreamPlanComponent(
      id: 'twitch-stream-info',
      onActivate: updateStreamInfo,
      activeConfigChanged: updateStreamInfo,
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
