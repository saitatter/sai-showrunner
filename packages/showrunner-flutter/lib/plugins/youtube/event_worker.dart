import 'dart:async';

import '../../services/plugin_event_hub.dart';
import '../../services/bounded_event_stream.dart';
import '../runtime/provider_event.dart';
import '../runtime/provider_worker_status.dart';
import 'actions.dart';
import 'event_parser.dart';

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
  bool _acceptPolls = true;
  int _generation = 0;
  Future<void>? _pendingPoll;
  final Set<String> _seenMessages = {};
  Object? lastError;
  ProviderWorkerState _state = ProviderWorkerState.stopped;
  DateTime? lastSuccessAt;

  bool get isRunning => _running;
  ProviderWorkerState get state => _state;
  int get failureCount => _failureCount;

  void start() {
    if (_running) return;
    _running = true;
    _acceptPolls = true;
    _setState(ProviderWorkerState.starting);
    _schedule(Duration.zero);
  }

  Future<void> pollOnce() {
    if (!_acceptPolls) return Future.value();
    final pending = _pendingPoll;
    if (pending != null) return pending;
    late final Future<void> operation;
    operation = _pollOnce(_generation).whenComplete(() {
      if (identical(_pendingPoll, operation)) _pendingPoll = null;
    });
    _pendingPoll = operation;
    return operation;
  }

  Future<void> _pollOnce(int generation) async {
    try {
      final response = await request('GET', '/youtube/v3/liveChat/messages', {
        'liveChatId': liveChatId,
        'part': 'snippet,authorDetails',
        if (_pageToken != null) 'pageToken': _pageToken,
      }, null);
      if (!_acceptPolls || generation != _generation) return;
      _failureCount = 0;
      lastError = null;
      lastSuccessAt = DateTime.now();
      _setState(ProviderWorkerState.running);
      final items = response['items'];
      if (items is List) {
        for (final item in items.whereType<Map>()) {
          final data = Map<String, dynamic>.from(item);
          final providerId = data['id']?.toString();
          if (providerId?.isNotEmpty == true &&
              _seenMessages.contains(providerId)) {
            continue;
          }
          final type = (data['snippet'] as Map?)?['type']?.toString();
          final eventId = youTubeDomainEventType(type);
          eventHub.emitProviderEvent(
            ProviderEventEnvelope(
              platform: ProviderPlatform.youtube,
              eventType: eventId,
              providerEventId: providerId,
              channelId: liveChatId,
              occurredAt:
                  DateTime.tryParse(
                    '${(data['snippet'] as Map?)?['publishedAt']}',
                  ) ??
                  DateTime.now().toUtc(),
              payload: flattenYouTubeEvent(data, eventType: type),
            ),
          );
          if (providerId?.isNotEmpty == true) {
            _seenMessages.add(providerId!);
            if (_seenMessages.length > 4096) {
              _seenMessages.remove(_seenMessages.first);
            }
          }
        }
      }
      _pageToken = response['nextPageToken']?.toString() ?? _pageToken;
    } catch (error) {
      if (!_acceptPolls || generation != _generation) return;
      _failureCount++;
      lastError = error;
      onError?.call(error);
      if (error is EventBackpressureException) {
        _running = false;
        _acceptPolls = false;
        _timer?.cancel();
        _timer = null;
        _setState(ProviderWorkerState.error);
        return;
      }
      _setState(
        _running ? ProviderWorkerState.reconnecting : ProviderWorkerState.error,
      );
    }
    if (_running && generation == _generation) {
      final multiplier = 1 << _failureCount.clamp(0, 6);
      _schedule(_failureCount == 0 ? interval : _boundedBackoff(multiplier));
    }
  }

  Future<void> stop() async {
    _running = false;
    _acceptPolls = false;
    _generation++;
    _pendingPoll = null;
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
