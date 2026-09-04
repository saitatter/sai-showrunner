import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../schema/automation.dart';
import '../../services/plugin_event_hub.dart';
import '../../services/http_provider_transports.dart';
import '../twitch/event_worker.dart';
import '../youtube/event_worker.dart';
import '../youtube/actions.dart';
import '../../services/showrunner_data_service.dart';
import 'provider_worker_status.dart';

export '../twitch/event_worker.dart';
export '../youtube/event_worker.dart';
export 'provider_worker_status.dart';

final class ProviderEventRuntime extends ChangeNotifier {
  ProviderEventRuntime({required this.dataService, required this.eventHub});

  final ShowRunnerDataService dataService;
  final DartPluginEventHub eventHub;
  final Map<String, List<JsonMap>> _activeProfileTriggerSets = {};
  TwitchEventSubWorker? twitch;
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
    notifyListeners();
  }

  Future<Map<String, dynamic>> discoverYouTubeBroadcast() async {
    final request = await _resolveYouTubeRequest();
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
    notifyListeners();
    return _youtubeBroadcast ?? <String, dynamic>{};
  }

  void simulateYouTubeChatMessage({
    String author = 'Simulated Viewer',
    String message = '!hello chat',
  }) {
    eventHub.emit('chatMessage', {
      'id': 'simulated-${DateTime.now().microsecondsSinceEpoch}',
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
    });
  }

  Future<YouTubeRequest?> _resolveYouTubeRequest() async {
    if (_youtubeRequest != null) return _youtubeRequest;
    final settings = await dataService.loadPluginSettings('youtube');
    final accessToken = settings['accessToken'] as String?;
    if (accessToken?.isNotEmpty != true) return null;
    _youtubeRequest = JsonHttpTransport(
      baseUrl: 'https://www.googleapis.com',
      accessToken: accessToken,
    ).request;
    return _youtubeRequest;
  }

  Future<void> startYouTubeChat({String? liveChatId}) async {
    final settings = await dataService.loadPluginSettings('youtube');
    final resolvedId =
        liveChatId ?? _youtubeLiveChatId ?? settings['liveChatId'] as String?;
    final request = await _resolveYouTubeRequest();
    if (request == null || resolvedId == null || resolvedId.isEmpty) {
      throw StateError('YouTube access token and live chat ID are required.');
    }
    await youtube?.stop();
    youtube = YouTubeLiveChatWorker(
      request: request,
      eventHub: eventHub,
      liveChatId: resolvedId,
      onStatusChanged: notifyListeners,
    );
    youtube!.start();
    _youtubeLiveChatId = resolvedId;
    notifyListeners();
  }

  Future<void> stopYouTubeChat() async {
    await youtube?.stop();
    youtube = null;
    notifyListeners();
  }

  Future<void> startTwitch() async {
    await _startTwitch(await dataService.loadPluginSettings('twitch'));
  }

  Future<void> _startTwitch(Map<String, dynamic> twitchSettings) async {
    final twitchToken = twitchSettings['accessToken'] as String?;
    final twitchClientId = twitchSettings['clientId'] as String?;
    final broadcasterId = twitchSettings['broadcasterId'] as String?;
    if (twitchToken?.isNotEmpty != true ||
        twitchClientId?.isNotEmpty != true ||
        broadcasterId?.isNotEmpty != true) {
      throw StateError(
        'Twitch access token, client ID, and broadcaster ID are required.',
      );
    }
    await twitch?.stop();
    final transport = JsonHttpTransport(
      baseUrl: 'https://api.twitch.tv',
      accessToken: twitchToken,
      headers: {'Client-Id': twitchClientId!},
    );
    twitch = TwitchEventSubWorker(
      accessToken: twitchToken!,
      clientId: twitchClientId,
      broadcasterId: broadcasterId!,
      request: transport.request,
      eventHub: eventHub,
      onStatusChanged: notifyListeners,
    );
    await twitch!.start();
    notifyListeners();
  }

  Future<void> stopTwitch() async {
    await twitch?.stop();
    twitch = null;
    notifyListeners();
  }

  Future<void> start() async {
    final twitchSettings = await dataService.loadPluginSettings('twitch');
    final youtubeSettings = await dataService.loadPluginSettings('youtube');
    final twitchToken = twitchSettings['accessToken'] as String?;
    if (twitchToken?.isNotEmpty == true &&
        (twitchSettings['clientId'] as String?)?.isNotEmpty == true &&
        (twitchSettings['broadcasterId'] as String?)?.isNotEmpty == true) {
      await _startTwitch(twitchSettings);
    }
    final youtubeToken = youtubeSettings['accessToken'] as String?;
    final liveChatId = youtubeSettings['liveChatId'] as String?;
    if (youtubeToken?.isNotEmpty == true && liveChatId?.isNotEmpty == true) {
      final transport = JsonHttpTransport(
        baseUrl: 'https://www.googleapis.com',
        accessToken: youtubeToken,
      );
      _youtubeRequest = transport.request;
      _youtubeLiveChatId = liveChatId;
      youtube = YouTubeLiveChatWorker(
        request: transport.request,
        eventHub: eventHub,
        liveChatId: liveChatId!,
        onStatusChanged: notifyListeners,
      );
      youtube!.start();
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await twitch?.stop();
    await youtube?.stop();
    twitch = null;
    youtube = null;
    _youtubeRequest = null;
    _youtubeLiveChatId = null;
    notifyListeners();
  }
}
