import '../runtime/provider_operation_policy.dart';
import 'dart:async';
import '../../runtime/expression.dart';
import '../../services/http_provider_transports.dart';
import '../../services/plugin_event_hub.dart';
import '../../services/showrunner_data_service.dart';
import '../registry/plugin_oauth.dart';
import '../registry/plugin_registry.dart';
import '../stream_plans/manifest.dart';
import 'account_runtime.dart';
import 'actions.dart';

Future<void> registerConfiguredTwitch(
  DartPluginRegistry registry, {
  required ShowRunnerDataService dataService,
  required DartPluginEventHub? eventHub,
  required DartStreamPlanRuntime activeStreamPlans,
}) async {
  final scope = ProviderOperationScope();
  final twitch = await loadTwitchChannelSettings(dataService);
  final twitchClientId = twitch['clientId'] as String?;
  final twitchManager = createPluginTokenManager(
    pluginId: 'twitch',
    settings: twitch,
    dataService: dataService,
    endpoint: 'https://id.twitch.tv/oauth2/token',
  );
  final twitchTransport = twitchManager != null
      ? JsonHttpTransport(
          operationScope: scope,
          baseUrl: 'https://api.twitch.tv',
          accessTokenProvider: twitchManager.accessToken,
          headers: {
            if (twitchClientId != null && twitchClientId.isNotEmpty)
              'Client-Id': twitchClientId,
          },
        )
      : null;
  final configuredTwitchTransport = TwitchTransport.withDefaults(
    (method, path, query, body) async {
      if (twitchTransport == null) {
        return _unconfiguredTwitch(method, path, query, body);
      }
      return twitchTransport.request(method, path, query, body);
    },
    broadcasterId: twitch['broadcasterId']?.toString(),
    moderatorId:
        twitch['moderatorId']?.toString() ??
        twitch['broadcasterId']?.toString(),
  );
  registry.register(
    createTwitchPlugin(
      configuredTwitchTransport,
      eventHub: eventHub,
      viewerGroupRepository: dataService.storage.resource(
        const ResourceTypeId('CustomTwitchViewerGroup'),
      ),
    ),

    initialHealth: (twitchTransport != null)
        ? const DartPluginHealth.connectionUnchecked()
        : const DartPluginHealth.notConfigured(),
    onStop: scope.close,
  );
  _registerTwitchStreamPlanComponent(
    runtime: activeStreamPlans,
    transport: configuredTwitchTransport,
    broadcasterId: twitch['broadcasterId']?.toString(),
  );
}

void registerDefaultTwitch(
  DartPluginRegistry registry, {
  required DartPluginEventHub? eventHub,
  required DartStreamPlanRuntime activeStreamPlans,
}) {
  registry.register(
    createTwitchPlugin(
      TwitchTransport(_unconfiguredTwitch),
      eventHub: eventHub,
    ),

    initialHealth: const DartPluginHealth.notConfigured(),
  );
  _registerTwitchStreamPlanComponent(
    runtime: activeStreamPlans,
    transport: TwitchTransport(_unconfiguredTwitch),
  );
}

void _registerTwitchStreamPlanComponent({
  required TwitchTransport transport,
  required DartStreamPlanRuntime runtime,
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

  runtime.registerComponentType(
    DartStreamPlanComponent(
      id: 'twitch-stream-info',
      onActivate: updateStreamInfo,
      activeConfigChanged: updateStreamInfo,
    ),
  );
}

Future<RuntimeMap> _unconfiguredTwitch(
  String method,
  String path,
  RuntimeMap query,
  RuntimeMap body,
) =>
    Future<RuntimeMap>.error(StateError('Twitch transport is not configured.'));
