import 'dart:async';
import 'dart:convert';

import '../../services/plugin_event_hub.dart';
import '../../services/bounded_event_stream.dart';
import '../../runtime/expression.dart';
import '../runtime/provider_event.dart';
import '../runtime/provider_worker_status.dart';
import 'actions.dart';

import 'eventsub_socket.dart';
import 'eventsub_subscriptions.dart';
import 'event_parser.dart';

export 'eventsub_socket.dart';
export 'eventsub_subscriptions.dart';

final class TwitchEventSubWorker {
  TwitchEventSubWorker({
    required this.accessToken,
    required this.clientId,
    required this.broadcasterId,
    required this.request,
    required this.eventHub,
    this.socketFactory = connectEventSubSocket,
    this.reconnectDelay = const Duration(seconds: 2),
    this.maxReconnectAttempts = 5,
    this.onStatusChanged,
    List<String>? subscriptionTypes,
    List<TwitchEventSubSubscription>? subscriptions,
    this.ignoreSubscriptionErrors = true,
    this.adSchedulePollInterval = const Duration(minutes: 1),
    this.welcomeTimeout = const Duration(seconds: 15),
  }) : _subscriptions =
           subscriptions ??
           (subscriptionTypes == null
               ? defaultTwitchEventSubSubscriptions(broadcasterId)
               : subscriptionTypes
                     .map(
                       (type) => TwitchEventSubSubscription(
                         type: type,
                         version: type == 'channel.moderate' ? '2' : '1',
                         condition: {
                           'broadcaster_user_id': broadcasterId,
                           'user_id': broadcasterId,
                         },
                       ),
                     )
                     .toList());

  final String accessToken;
  final String clientId;
  final String broadcasterId;
  final TwitchRequest request;
  final DartPluginEventHub eventHub;
  final EventSubSocketFactory socketFactory;
  final Duration reconnectDelay;
  final int maxReconnectAttempts;
  final void Function()? onStatusChanged;
  final bool ignoreSubscriptionErrors;
  final Duration adSchedulePollInterval;
  final Duration welcomeTimeout;
  final _seenMessages = <String>{};
  Timer? _keepaliveTimer;
  Duration? _keepaliveTimeout;
  int _generation = 0;
  Completer<String>? _welcome;
  final List<TwitchEventSubSubscription> _subscriptions;
  EventSubSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  bool _stopping = false;
  bool _reconnecting = false;
  ProviderWorkerState _state = ProviderWorkerState.stopped;
  Object? lastError;
  int reconnectAttempts = 0;
  DateTime? connectedAt;
  List<String> subscriptionErrors = const [];
  Object? adScheduleError;
  Timer? _adScheduleTimer;
  Timer? _adEndTimer;
  String? _lastAdSchedule;
  bool _loadingAdSchedule = false;

  ProviderWorkerState get state => _state;
  bool get isRunning => _state == ProviderWorkerState.running;
  bool get isReconnecting => _state == ProviderWorkerState.reconnecting;

  List<String> get subscriptionTypes =>
      _subscriptions.map((subscription) => subscription.type).toList();

  Future<void> start() async {
    if (isRunning || _state == ProviderWorkerState.starting || _reconnecting) {
      return;
    }
    _stopping = false;
    lastError = null;
    reconnectAttempts = 0;
    _setState(ProviderWorkerState.starting);
    final generation = _generation;
    try {
      await _connect();
    } catch (error) {
      if (generation != _generation) return;
      lastError = error;
      await _disposeConnection();
      if (_stopping) return;
      _setState(ProviderWorkerState.error);
      rethrow;
    }
  }

  Future<void> _connect({Uri? reconnectUri}) async {
    final generation = _generation;
    final socket = await socketFactory(
      reconnectUri ?? Uri.parse('wss://eventsub.wss.twitch.tv/ws'),
    );
    if (_stopping || generation != _generation) {
      await socket.close();
      throw StateError('Twitch EventSub connection was cancelled.');
    }
    final previousSocket = _socket;
    final previousSubscription = _subscription;
    if (reconnectUri == null) _socket = socket;
    final welcomeCompleter = Completer<String>();
    _welcome = welcomeCompleter;
    final subscription = socket.messages.listen(
      (raw) {
        if (!welcomeCompleter.isCompleted) {
          if (raw is String) {
            welcomeCompleter.complete(raw);
          } else {
            welcomeCompleter.completeError(
              StateError('Twitch EventSub welcome was not text.'),
            );
          }
          return;
        }
        if (!_stopping && identical(_socket, socket)) {
          _resetKeepalive();
          try {
            _handleMessage(raw);
          } on FormatException {
            // A malformed frame must not terminate event delivery.
          } on EventBackpressureException catch (error) {
            _failBackpressure(error);
          }
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!welcomeCompleter.isCompleted) {
          welcomeCompleter.completeError(error, stackTrace);
        } else if (identical(_socket, socket)) {
          lastError = error;
          _handleClosed();
        }
      },
      onDone: () {
        if (!welcomeCompleter.isCompleted) {
          welcomeCompleter.completeError(
            StateError('Twitch EventSub socket closed before welcome.'),
          );
        } else if (identical(_socket, socket)) {
          _handleClosed();
        }
      },
    );
    if (reconnectUri == null) _subscription = subscription;
    Map welcome;
    try {
      welcome =
          jsonDecode(await welcomeCompleter.future.timeout(welcomeTimeout))
              as Map;
    } catch (_) {
      await subscription.cancel();
      await socket.close();
      rethrow;
    }
    if (_stopping || generation != _generation) {
      await subscription.cancel();
      await socket.close();
      throw StateError('Twitch EventSub connection was cancelled.');
    }
    final session = (welcome['payload'] as Map?)?['session'] as Map?;
    final sessionId = session?['id']?.toString();
    if (sessionId == null || sessionId.isEmpty) {
      await subscription.cancel();
      await socket.close();
      throw StateError('Twitch EventSub welcome did not contain a session ID.');
    }
    _socket = socket;
    _subscription = subscription;
    final timeoutSeconds = session?['keepalive_timeout_seconds'];
    _keepaliveTimeout = timeoutSeconds is num && timeoutSeconds > 0
        ? Duration(milliseconds: (timeoutSeconds * 1000).round())
        : null;
    _resetKeepalive();
    if (reconnectUri != null) {
      await previousSubscription?.cancel();
      await previousSocket?.close();
    }
    final subscriptionErrors = <String>[];
    for (final subscriptionRequest
        in reconnectUri == null
            ? _subscriptions
            : <TwitchEventSubSubscription>[]) {
      if (_stopping || generation != _generation) return;
      try {
        await request('POST', '/helix/eventsub/subscriptions', {}, {
          'type': subscriptionRequest.type,
          'version': subscriptionRequest.version,
          'condition': subscriptionRequest.condition,
          'transport': {'method': 'websocket', 'session_id': sessionId},
        });
      } catch (error) {
        subscriptionErrors.add('${subscriptionRequest.type}: $error');
        if (!ignoreSubscriptionErrors) rethrow;
      }
    }
    if (_stopping || generation != _generation || !identical(_socket, socket)) {
      return;
    }
    if (reconnectUri == null) {
      this.subscriptionErrors = List.unmodifiable(subscriptionErrors);
    }
    lastError = null;
    connectedAt = DateTime.now();
    _setState(ProviderWorkerState.running);
    if (_subscriptions.any((item) => item.type == 'channel.ad_break.begin')) {
      await _refreshAdSchedule();
      if (_stopping) return;
      _adScheduleTimer?.cancel();
      _adScheduleTimer = Timer.periodic(adSchedulePollInterval, (_) {
        unawaited(_refreshAdSchedule());
      });
    }
  }

  Future<void> _refreshAdSchedule() async {
    if (_stopping || _loadingAdSchedule) return;
    _loadingAdSchedule = true;
    try {
      final response = await request('GET', '/helix/channels/ads', {
        'broadcaster_id': broadcasterId,
      }, {});
      if (_stopping) return;
      final data = response['data'];
      if (data is List && data.isNotEmpty && data.first is Map) {
        final schedule = Map<String, dynamic>.from(data.first as Map);
        final fingerprint = jsonEncode(schedule);
        if (fingerprint != _lastAdSchedule) {
          _emitDomainEvent('adSchedule', {
            ...schedule,
            'eventType': 'adSchedule',
            'platform': 'twitch',
          });
          _lastAdSchedule = fingerprint;
        }
      }
      adScheduleError = null;
    } catch (error) {
      adScheduleError = error;
      if (error is EventBackpressureException) _failBackpressure(error);
    } finally {
      _loadingAdSchedule = false;
    }
  }

  Future<void> stop() async {
    _stopping = true;
    _generation++;
    _adScheduleTimer?.cancel();
    _adScheduleTimer = null;
    _adEndTimer?.cancel();
    _adEndTimer = null;
    await _disposeConnection();
    _reconnecting = false;
    _setState(ProviderWorkerState.stopped);
  }

  void _handleClosed() {
    unawaited(_disposeConnection());
    _adScheduleTimer?.cancel();
    _adScheduleTimer = null;
    if (_stopping) {
      _setState(ProviderWorkerState.stopped);
    } else {
      _setState(ProviderWorkerState.reconnecting);
      unawaited(_reconnect());
    }
  }

  Future<void> _reconnect() async {
    if (_reconnecting || _stopping) return;
    _reconnecting = true;
    final generation = _generation;
    _setState(ProviderWorkerState.reconnecting);
    try {
      for (
        var attempt = 0;
        attempt < maxReconnectAttempts &&
            !_stopping &&
            generation == _generation;
        attempt++
      ) {
        reconnectAttempts = attempt + 1;
        final multiplier = 1 << attempt;
        await Future<void>.delayed(reconnectDelay * multiplier);
        if (_stopping || generation != _generation) return;
        try {
          await _connect();
          return;
        } catch (error) {
          if (generation != _generation) return;
          lastError = error;
          await _disposeConnection();
          _setState(ProviderWorkerState.error);
        }
      }
    } finally {
      if (generation == _generation) {
        _reconnecting = false;
        if (_stopping) {
          _setState(ProviderWorkerState.stopped);
        } else if (!isRunning) {
          _setState(ProviderWorkerState.error);
        }
      }
    }
  }

  void _setState(ProviderWorkerState value) {
    _state = value;
    onStatusChanged?.call();
  }

  void _handleMessage(dynamic raw) {
    if (raw is! String) return;
    final message = jsonDecode(raw);
    if (message is! Map || message['metadata'] is! Map) return;
    final metadata = Map<String, dynamic>.from(message['metadata'] as Map);
    if (metadata['message_type'] == 'session_reconnect') {
      final session = (message['payload'] as Map?)?['session'] as Map?;
      final url = session?['reconnect_url'];
      if (url is String && !_reconnecting) {
        unawaited(_handover(Uri.parse(url)));
      }
      return;
    }
    if (metadata['message_type'] != 'notification') return;
    final payload = message['payload'];
    if (payload is! Map) return;
    final subscription = payload['subscription'];
    final event = payload['event'];
    if (subscription is! Map || event is! Map) return;
    final messageId = metadata['message_id']?.toString();
    if (messageId != null && messageId.isNotEmpty) {
      if (_seenMessages.contains(messageId)) return;
    }
    final type = subscription['type']?.toString();
    final eventId = twitchDomainEventType(type, event, broadcasterId);
    if (eventId != null) {
      _emitDomainEvent(
        eventId,
        {
          ...normalizeTwitchEvent(eventId, event),
          if (metadata['message_timestamp'] is String)
            'providerTime': metadata['message_timestamp'],
        },
        providerEventId: messageId,
        occurredAt: DateTime.tryParse('${metadata['message_timestamp']}'),
      );
      if (messageId != null && messageId.isNotEmpty) {
        _seenMessages.add(messageId);
        if (_seenMessages.length > 4096) {
          _seenMessages.remove(_seenMessages.first);
        }
      }
      if (eventId == 'adStarted') {
        _adEndTimer?.cancel();
        final seconds = int.tryParse('${event['duration_seconds']}');
        if (seconds != null && seconds > 0) {
          final start =
              DateTime.tryParse('${event['started_at']}') ?? DateTime.now();
          final delay = start
              .add(Duration(seconds: seconds))
              .difference(DateTime.now());
          _adEndTimer = Timer(delay.isNegative ? Duration.zero : delay, () {
            if (!_stopping) {
              try {
                _emitDomainEvent(
                  'adEnded',
                  normalizeTwitchEvent('adEnded', event),
                );
              } on EventBackpressureException catch (error) {
                _failBackpressure(error);
              }
            }
          });
        }
        unawaited(_refreshAdSchedule());
      }
    }
  }

  void _emitDomainEvent(
    String eventType,
    RuntimeMap payload, {
    String? providerEventId,
    DateTime? occurredAt,
  }) {
    eventHub.emitProviderEvent(
      ProviderEventEnvelope(
        platform: ProviderPlatform.twitch,
        eventType: eventType,
        providerEventId: providerEventId,
        accountId: broadcasterId,
        channelId: eventType == 'twitchWhisper' ? null : broadcasterId,
        visibility: eventType == 'twitchWhisper'
            ? ProviderEventVisibility.private
            : ProviderEventVisibility.public,
        occurredAt: occurredAt ?? DateTime.now().toUtc(),
        payload: payload,
      ),
    );
  }

  void _failBackpressure(EventBackpressureException error) {
    lastError = error;
    // Stop the socket immediately. Reconnection requires an explicit user action
    // after consumers recover, so overload is visible rather than silently lossy.
    unawaited(stop().then((_) => _setState(ProviderWorkerState.error)));
  }

  Future<void> _disposeConnection() async {
    final welcome = _welcome;
    _welcome = null;
    if (welcome != null && !welcome.isCompleted) {
      welcome.completeError(
        StateError('Twitch EventSub connection was cancelled.'),
      );
    }
    _keepaliveTimer?.cancel();
    _keepaliveTimer = null;
    final subscription = _subscription;
    final socket = _socket;
    _subscription = null;
    _socket = null;
    await subscription?.cancel();
    await socket?.close();
  }

  void _resetKeepalive() {
    _keepaliveTimer?.cancel();
    final timeout = _keepaliveTimeout;
    if (timeout != null && !_stopping) {
      _keepaliveTimer = Timer(timeout, () {
        lastError = TimeoutException(
          'Twitch EventSub keepalive timed out.',
          timeout,
        );
        _handleClosed();
      });
    }
  }

  Future<void> _handover(Uri uri) async {
    final generation = _generation;
    _reconnecting = true;
    _setState(ProviderWorkerState.reconnecting);
    try {
      await _connect(reconnectUri: uri);
    } catch (error) {
      if (generation != _generation) return;
      lastError = error;
      await _disposeConnection();
    } finally {
      if (generation == _generation) _reconnecting = false;
    }
    if (!_stopping && !isRunning) unawaited(_reconnect());
  }
}
