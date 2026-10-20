import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../schema/json.dart';
import '../../services/plugin_event_hub.dart';
import '../twitch/connection_factory.dart';
import '../youtube/connection_factory.dart';
import 'provider_operation_policy.dart';
import 'provider_event.dart';
import '../twitch/event_worker.dart';
import '../twitch/account_runtime.dart';
import '../youtube/event_worker.dart';
import '../youtube/actions.dart';
import '../../services/showrunner_data_service.dart';
import 'provider_worker_status.dart';

export '../twitch/event_worker.dart';
export '../youtube/event_worker.dart';
export 'provider_worker_status.dart';

final class ProviderEventRuntime extends ChangeNotifier {
  ProviderEventRuntime({
    required this.dataService,
    required this.eventHub,
    this.twitchRequestFactory = createTwitchRuntimeRequest,
    this.youtubeRequestFactory = createYouTubeRuntimeRequest,
    this.twitchSocketFactory = connectEventSubSocket,
  });

  final TwitchRuntimeRequestFactory twitchRequestFactory;
  final YouTubeRuntimeRequestFactory youtubeRequestFactory;
  final EventSubSocketFactory twitchSocketFactory;
  ProviderOperationScope? _twitchScope;
  ProviderOperationScope? _botScope;
  ProviderOperationScope? _youtubeScope;
  Future<YouTubeRequest?>? _resolvingYouTube;
  int _twitchGeneration = 0;
  int _youtubeGeneration = 0;
  bool _disposed = false;

  bool _currentTwitch(int generation) =>
      !_disposed && generation == _twitchGeneration;
  bool _currentYouTube(int generation) =>
      !_disposed && generation == _youtubeGeneration;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _requireOpen() {
    if (_disposed) throw StateError('Provider runtime is disposed.');
  }

  void _requireYouTube(int generation) {
    if (!_currentYouTube(generation)) {
      throw StateError('YouTube operation was cancelled.');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _twitchGeneration++;
    _youtubeGeneration++;
    super.dispose();
  }

  final ShowRunnerDataService dataService;
  final DartPluginEventHub eventHub;
  final Map<String, List<JsonMap>> _activeProfileTriggerSets = {};
  TwitchEventSubWorker? twitch;
  TwitchEventSubWorker? botWhispers;
  YouTubeLiveChatWorker? youtube;
  YouTubeRequest? _youtubeRequest;
  String? _youtubeLiveChatId;
  Map<String, dynamic>? _youtubeBroadcast;

  bool get twitchRunning => twitch?.isRunning == true;
  bool get youtubeRunning => youtube?.isRunning == true;

  bool get youtubeChatRunning => youtube?.isRunning == true;

  Object? get youtubeLastError => youtube?.lastError;
  ProviderWorkerState get twitchState =>
      twitch?.state ?? ProviderWorkerState.stopped;
  ProviderWorkerState get youtubeState =>
      youtube?.state ?? ProviderWorkerState.stopped;
  Object? get twitchLastError => twitch?.lastError;
  int get twitchReconnectAttempts => twitch?.reconnectAttempts ?? 0;
  List<String> get twitchSubscriptionErrors =>
      twitch?.subscriptionErrors ?? const [];
  int get youtubeFailureCount => youtube?.failureCount ?? 0;

  Map<String, dynamic>? get youtubeBroadcast => _youtubeBroadcast;

  Iterable<JsonMap> get activeProfileTriggers sync* {
    for (final triggers in _activeProfileTriggerSets.values) {
      for (final trigger in triggers) {
        yield Map<String, dynamic>.from(trigger);
      }
    }
  }

  void updateProfileActivity(
    String profileId, {
    required bool active,
    Iterable<JsonMap> triggers = const [],
  }) {
    if (active) {
      _activeProfileTriggerSets[profileId] = triggers
          .map((trigger) => Map<String, dynamic>.from(trigger))
          .toList();
    } else {
      _activeProfileTriggerSets.remove(profileId);
    }
    _notify();
  }

  Future<Map<String, dynamic>> discoverYouTubeBroadcast() async {
    _requireOpen();
    final generation = _youtubeGeneration;
    final request = await _resolveYouTubeRequest(generation);
    _requireYouTube(generation);
    if (request == null) {
      throw StateError(
        'YouTube access token is required for broadcast discovery.',
      );
    }
    final response = await request('GET', '/youtube/v3/liveBroadcasts', {
      'part': 'snippet',
      'broadcastStatus': 'active',
      'maxResults': '1',
    }, null);
    _requireYouTube(generation);
    final items = response['items'];
    final item = items is List && items.isNotEmpty && items.first is Map
        ? Map<String, dynamic>.from(items.first as Map)
        : null;
    final snippet = item?['snippet'] is Map
        ? Map<String, dynamic>.from(item!['snippet'] as Map)
        : const <String, dynamic>{};
    var broadcastId = item?['id']?.toString();
    var title = snippet['title']?.toString();
    var liveChatId = snippet['liveChatId']?.toString();
    if (liveChatId == null || liveChatId.isEmpty) {
      final search = await request('GET', '/youtube/v3/search', {
        'part': 'snippet',
        'forMine': 'true',
        'type': 'video',
        'eventType': 'live',
        'maxResults': '5',
      }, null);
      _requireYouTube(generation);
      final searchItems = search['items'];
      final videoIds = searchItems is List
          ? searchItems
                .whereType<Map>()
                .map((value) => (value['id'] as Map?)?['videoId']?.toString())
                .whereType<String>()
                .toList()
          : <String>[];
      if (videoIds.isNotEmpty) {
        final videos = await request('GET', '/youtube/v3/videos', {
          'part': 'snippet,liveStreamingDetails',
          'id': videoIds.join(','),
        }, null);
        _requireYouTube(generation);
        final videoItems = videos['items'];
        final video =
            videoItems is List &&
                videoItems.isNotEmpty &&
                videoItems.first is Map
            ? Map<String, dynamic>.from(videoItems.first as Map)
            : null;
        final streaming = video?['liveStreamingDetails'] as Map?;
        broadcastId = video?['id']?.toString() ?? broadcastId;
        title = (video?['snippet'] as Map?)?['title']?.toString() ?? title;
        liveChatId = streaming?['activeLiveChatId']?.toString();
      }
    }
    _youtubeBroadcast = broadcastId == null
        ? null
        : {
            'id': broadcastId,
            'title': title,
            'status': liveChatId == null ? 'unknown' : 'live',
            'liveChatId': liveChatId,
          };
    _notify();
    return _youtubeBroadcast ?? <String, dynamic>{};
  }

  void simulateYouTubeChatMessage({
    String author = 'Simulated Viewer',
    String message = '!hello chat',
  }) {
    _requireOpen();
    final now = DateTime.now().toUtc();
    final id = 'simulated-${now.microsecondsSinceEpoch}';
    eventHub.emitProviderEvent(
      ProviderEventEnvelope(
        platform: ProviderPlatform.youtube,
        eventType: 'chatMessage',
        occurredAt: now,
        providerEventId: id,
        channelId: _youtubeLiveChatId,
        payload: {
          'id': id,
          'snippet': {
            'type': 'textMessageEvent',
            'displayMessage': message,
            'publishedAt': DateTime.now().toUtc().toIso8601String(),
          },
          'authorDetails': {
            'displayName': author,
            'isChatModerator': false,
            'isChatOwner': false,
          },
        },
      ),
    );
  }

  Future<YouTubeRequest?> _resolveYouTubeRequest(int generation) async {
    _requireYouTube(generation);
    if (_youtubeRequest != null) return _youtubeRequest;
    if (_resolvingYouTube != null) return _resolvingYouTube;
    final resolving = _loadYouTubeRequest(generation);
    _resolvingYouTube = resolving;
    try {
      return await resolving;
    } finally {
      if (identical(_resolvingYouTube, resolving)) _resolvingYouTube = null;
    }
  }

  Future<YouTubeRequest?> _loadYouTubeRequest(int generation) async {
    final settings = await dataService.loadPluginSettings('youtube');
    _requireYouTube(generation);
    final accessToken = settings['accessToken'] as String?;
    if (accessToken?.isNotEmpty != true) return null;
    final scope = ProviderOperationScope();
    _youtubeScope = scope;
    _youtubeRequest = youtubeRequestFactory(
      accessToken: accessToken!,
      scope: scope,
    );
    return _youtubeRequest;
  }

  Future<void> startYouTubeChat({String? liveChatId}) async {
    _requireOpen();
    final generation = ++_youtubeGeneration;
    await _stopYouTubeOwned();
    if (!_currentYouTube(generation)) return;
    final settings = await dataService.loadPluginSettings('youtube');
    if (!_currentYouTube(generation)) return;
    final resolvedId =
        liveChatId ?? _youtubeLiveChatId ?? settings['liveChatId'] as String?;
    YouTubeRequest? request;
    try {
      request = await _resolveYouTubeRequest(generation);
    } catch (_) {
      if (!_currentYouTube(generation)) return;
      rethrow;
    }
    if (!_currentYouTube(generation)) return;
    if (request == null || resolvedId == null || resolvedId.isEmpty) {
      throw StateError('YouTube access token and live chat ID are required.');
    }
    youtube = YouTubeLiveChatWorker(
      request: request,
      eventHub: eventHub,
      liveChatId: resolvedId,
      onStatusChanged: _notify,
    );
    youtube!.start();
    _youtubeLiveChatId = resolvedId;
    _notify();
  }

  Future<void> _stopYouTubeOwned() async {
    final worker = youtube;
    final scope = _youtubeScope;
    youtube = null;
    _youtubeScope = null;
    _youtubeRequest = null;
    _resolvingYouTube = null;
    final stopping = worker?.stop();
    await scope?.close();
    await stopping;
  }

  Future<void> stopYouTubeChat() async {
    _youtubeGeneration++;
    await _stopYouTubeOwned();
    _notify();
  }

  Future<void> startTwitch() async {
    _requireOpen();
    final generation = ++_twitchGeneration;
    await _stopTwitchOwned();
    if (!_currentTwitch(generation)) return;
    final settings = await loadTwitchChannelSettings(dataService);
    if (!_currentTwitch(generation)) return;
    await _startTwitch(settings, generation);
  }

  Future<void> _startTwitch(
    Map<String, dynamic> settings,
    int generation,
  ) async {
    final token = settings['accessToken'] as String?;
    final clientId = settings['clientId'] as String?;
    final broadcasterId = settings['broadcasterId'] as String?;
    if (token?.isNotEmpty != true ||
        clientId?.isNotEmpty != true ||
        broadcasterId?.isNotEmpty != true) {
      throw StateError(
        'Twitch access token, client ID, and broadcaster ID are required.',
      );
    }
    final scope = ProviderOperationScope();
    _twitchScope = scope;
    final worker = TwitchEventSubWorker(
      accessToken: token!,
      clientId: clientId!,
      broadcasterId: broadcasterId!,
      request: twitchRequestFactory(
        accessToken: token,
        clientId: clientId,
        scope: scope,
      ),
      socketFactory: twitchSocketFactory,
      eventHub: eventHub,
      onStatusChanged: _notify,
    );
    twitch = worker;
    try {
      await worker.start();
      if (!_currentTwitch(generation)) return;
      final bot = await TwitchAccountAuthService(
        dataService: dataService,
      ).loadAccount('bot');
      if (!_currentTwitch(generation)) return;
      final botToken = bot?.config['accessToken']?.toString() ?? '';
      final botId = bot?.config['twitchId']?.toString() ?? '';
      if (botToken.isNotEmpty && botId.isNotEmpty && botId != broadcasterId) {
        final botScope = ProviderOperationScope();
        _botScope = botScope;
        final botWorker = TwitchEventSubWorker(
          accessToken: botToken,
          clientId: clientId,
          broadcasterId: botId,
          request: twitchRequestFactory(
            accessToken: botToken,
            clientId: clientId,
            scope: botScope,
          ),
          socketFactory: twitchSocketFactory,
          eventHub: eventHub,
          onStatusChanged: _notify,
          subscriptions: [
            TwitchEventSubSubscription(
              type: 'user.whisper.message',
              version: '1',
              condition: {'user_id': botId},
            ),
          ],
        );
        botWhispers = botWorker;
        await botWorker.start();
      }
    } catch (_) {
      if (!_currentTwitch(generation)) return;
      rethrow;
    }
    if (_currentTwitch(generation)) _notify();
  }

  Future<void> _stopTwitchOwned() async {
    final channel = twitch;
    final bot = botWhispers;
    final scopes = [_twitchScope, _botScope];
    twitch = null;
    botWhispers = null;
    _twitchScope = null;
    _botScope = null;
    await Future.wait<void>([
      if (channel != null) channel.stop(),
      if (bot != null) bot.stop(),
      for (final scope in scopes)
        if (scope != null) scope.close(),
    ]);
  }

  Future<void> stopTwitch() async {
    _twitchGeneration++;
    await _stopTwitchOwned();
    _notify();
  }

  Future<void> start() async {
    _requireOpen();
    final twitchGeneration = ++_twitchGeneration;
    final youtubeGeneration = ++_youtubeGeneration;
    await Future.wait([_stopTwitchOwned(), _stopYouTubeOwned()]);
    final twitchSettings = await loadTwitchChannelSettings(dataService);
    final youtubeSettings = await dataService.loadPluginSettings('youtube');
    if (_currentTwitch(twitchGeneration) &&
        (twitchSettings['accessToken'] as String?)?.isNotEmpty == true &&
        (twitchSettings['clientId'] as String?)?.isNotEmpty == true &&
        (twitchSettings['broadcasterId'] as String?)?.isNotEmpty == true) {
      await _startTwitch(twitchSettings, twitchGeneration);
    }
    if (_currentYouTube(youtubeGeneration) &&
        (youtubeSettings['accessToken'] as String?)?.isNotEmpty == true &&
        (youtubeSettings['liveChatId'] as String?)?.isNotEmpty == true) {
      await startYouTubeChat(
        liveChatId: youtubeSettings['liveChatId'] as String,
      );
    }
  }

  Future<void> stop() async {
    // Both generations are invalidated before either platform can finish I/O.
    _twitchGeneration++;
    _youtubeGeneration++;
    final stopping = [_stopTwitchOwned(), _stopYouTubeOwned()];
    _youtubeLiveChatId = null;
    await Future.wait(stopping);
    _notify();
  }
}
