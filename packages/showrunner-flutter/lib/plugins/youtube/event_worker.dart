import 'dart:async';

import '../../services/plugin_event_hub.dart';
import '../../runtime/expression.dart';
import '../runtime/provider_worker_status.dart';
import 'actions.dart';

final class YouTubeLiveChatWorker {
  YouTubeLiveChatWorker({
    required this.request,
    required this.eventHub,
    required this.liveChatId,
    this.interval = const Duration(seconds: 5),
    this.maxBackoff = const Duration(minutes: 2),
    this.onError,
    this.onStatusChanged,
  });

  final YouTubeRequest request;
  final DartPluginEventHub eventHub;
  final String liveChatId;
  final Duration interval;
  final Duration maxBackoff;
  final void Function(Object error)? onError;
  final void Function()? onStatusChanged;
  Timer? _timer;
  String? _pageToken;
  int _failureCount = 0;
  bool _running = false;
  Object? lastError;
  ProviderWorkerState _state = ProviderWorkerState.stopped;
  DateTime? lastSuccessAt;

  bool get isRunning => _running;
  ProviderWorkerState get state => _state;
  int get failureCount => _failureCount;

  void start() {
    if (_running) return;
    _running = true;
    _setState(ProviderWorkerState.starting);
    _schedule(Duration.zero);
    _setState(ProviderWorkerState.running);
  }

  Future<void> pollOnce() async {
    try {
      final response = await request('GET', '/youtube/v3/liveChat/messages', {
        'liveChatId': liveChatId,
        'part': 'snippet,authorDetails',
        if (_pageToken != null) 'pageToken': _pageToken,
      }, null);
      _failureCount = 0;
      lastError = null;
      lastSuccessAt = DateTime.now();
      _setState(ProviderWorkerState.running);
      _pageToken = response['nextPageToken']?.toString() ?? _pageToken;
      final items = response['items'];
      if (items is List) {
        for (final item in items.whereType<Map>()) {
          final data = Map<String, dynamic>.from(item);
          final type = (data['snippet'] as Map?)?['type']?.toString();
          final eventId = switch (type) {
            'superChatEvent' => 'superChat',
            'superStickerEvent' => 'superSticker',
            'memberMilestoneChatEvent' || 'newSponsorEvent' => 'membership',
            _ => 'chatMessage',
          };
          eventHub.emit(eventId, _flattenYoutubeEvent(data, eventType: type));
        }
      }
    } catch (error) {
      _failureCount++;
      lastError = error;
      onError?.call(error);
      _setState(
        _running ? ProviderWorkerState.reconnecting : ProviderWorkerState.error,
      );
    }
    if (_running) {
      final multiplier = 1 << _failureCount.clamp(0, 6);
      _schedule(_failureCount == 0 ? interval : _boundedBackoff(multiplier));
    }
  }

  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
    _setState(ProviderWorkerState.stopped);
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(pollOnce()));
  }

  Duration _boundedBackoff(int multiplier) {
    final candidate = interval * multiplier;
    return candidate > maxBackoff ? maxBackoff : candidate;
  }

  void _setState(ProviderWorkerState value) {
    _state = value;
    onStatusChanged?.call();
  }
}

RuntimeMap _flattenYoutubeEvent(
  Map<String, dynamic> item, {
  String? eventType,
}) {
  final snippet = item['snippet'] is Map
      ? Map<String, dynamic>.from(item['snippet'] as Map)
      : const <String, dynamic>{};
  final author = item['authorDetails'] is Map
      ? Map<String, dynamic>.from(item['authorDetails'] as Map)
      : const <String, dynamic>{};
  final superChat = snippet['superChatDetails'] is Map
      ? Map<String, dynamic>.from(snippet['superChatDetails'] as Map)
      : const <String, dynamic>{};
  final superSticker = snippet['superStickerDetails'] is Map
      ? Map<String, dynamic>.from(snippet['superStickerDetails'] as Map)
      : const <String, dynamic>{};
  final membership = snippet['newSponsorDetails'] is Map
      ? Map<String, dynamic>.from(snippet['newSponsorDetails'] as Map)
      : const <String, dynamic>{};
  final textDetails = snippet['textMessageDetails'] is Map
      ? Map<String, dynamic>.from(snippet['textMessageDetails'] as Map)
      : const <String, dynamic>{};
  final message =
      textDetails['messageText'] ??
      superChat['userComment'] ??
      superSticker['userComment'] ??
      membership['memberLevelName'] ??
      '';
  final normalized = <String, dynamic>{
    'viewerId': author['channelId'] ?? '',
    'viewerName': author['displayName'] ?? '',
    'message': message,
    'messageId': item['id'] ?? '',
    'avatarUrl': author['profileImageUrl'] ?? '',
    'isModerator': author['isChatModerator'] == true,
    'isMember': author['isChatSponsor'] == true,
    'isOwner': author['isChatOwner'] == true,
  };
  void addIfPresent(String key, dynamic value) {
    if (value != null) normalized[key] = value;
  }

  addIfPresent('amountMicros', superChat['amountMicros']);
  addIfPresent('currency', superChat['currency']);
  addIfPresent('amountMicros', superSticker['amountMicros']);
  addIfPresent('currency', superSticker['currency']);
  addIfPresent('eventType', eventType);
  addIfPresent('memberLevelName', membership['memberLevelName']);
  addIfPresent('memberMonth', membership['memberMonth']);

  return {...item, ...normalized};
}
