import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../services/plugin_event_hub.dart';
import '../runtime/provider_worker_status.dart';
import 'actions.dart';

typedef EventSubSocketFactory = Future<EventSubSocket> Function(Uri uri);

abstract interface class EventSubSocket {
  Stream<dynamic> get messages;

  Future<void> close([int? code, String? reason]);
}

final class WebSocketEventSubSocket implements EventSubSocket {
  const WebSocketEventSubSocket(this.socket);

  final WebSocket socket;

  @override
  Stream<dynamic> get messages => socket;

  @override
  Future<void> close([int? code, String? reason]) => socket.close(code, reason);
}

final class TwitchEventSubWorker {
  TwitchEventSubWorker({
    required this.accessToken,
    required this.clientId,
    required this.broadcasterId,
    required this.request,
    required this.eventHub,
    this.socketFactory = _connectSocket,
    this.reconnectDelay = const Duration(seconds: 2),
    this.maxReconnectAttempts = 5,
    this.onStatusChanged,
    this.subscriptionTypes = const <String>[
      'channel.chat.message',
      'channel.ban',
      'channel.moderate',
    ],
  });

  final String accessToken;
  final String clientId;
  final String broadcasterId;
  final TwitchRequest request;
  final DartPluginEventHub eventHub;
  final EventSubSocketFactory socketFactory;
  final Duration reconnectDelay;
  final int maxReconnectAttempts;
  final void Function()? onStatusChanged;
  final List<String> subscriptionTypes;
  EventSubSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  bool _stopping = false;
  bool _reconnecting = false;
  ProviderWorkerState _state = ProviderWorkerState.stopped;
  Object? lastError;
  int reconnectAttempts = 0;
  DateTime? connectedAt;

  ProviderWorkerState get state => _state;
  bool get isRunning => _state == ProviderWorkerState.running;
  bool get isReconnecting => _state == ProviderWorkerState.reconnecting;

  Future<void> start() async {
    _stopping = false;
    lastError = null;
    reconnectAttempts = 0;
    _setState(ProviderWorkerState.starting);
    try {
      await _connect();
    } catch (error) {
      lastError = error;
      _socket = null;
      _setState(ProviderWorkerState.error);
      rethrow;
    }
  }

  Future<void> _connect() async {
    final socket = await socketFactory(
      Uri.parse('wss://eventsub.wss.twitch.tv/ws'),
    );
    _socket = socket;
    final welcomeCompleter = Completer<String>();
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
        _handleMessage(raw);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!welcomeCompleter.isCompleted) {
          welcomeCompleter.completeError(error, stackTrace);
        }
      },
      onDone: () {
        if (!welcomeCompleter.isCompleted) {
          welcomeCompleter.completeError(
            StateError('Twitch EventSub socket closed before welcome.'),
          );
        } else {
          _handleClosed();
        }
      },
    );
    _subscription = subscription;
    final welcome = jsonDecode(await welcomeCompleter.future) as Map;
    final session = (welcome['payload'] as Map?)?['session'] as Map?;
    final sessionId = session?['id']?.toString();
    if (sessionId == null || sessionId.isEmpty) {
      throw StateError('Twitch EventSub welcome did not contain a session ID.');
    }
    for (final type in subscriptionTypes) {
      await request('POST', '/helix/eventsub/subscriptions', {}, {
        'type': type,
        'version': '1',
        'condition': {
          'broadcaster_user_id': broadcasterId,
          'user_id': broadcasterId,
        },
        'transport': {'method': 'websocket', 'session_id': sessionId},
      });
    }
    connectedAt = DateTime.now();
    _setState(ProviderWorkerState.running);
  }

  Future<void> stop() async {
    _stopping = true;
    await _subscription?.cancel();
    _subscription = null;
    final socket = _socket;
    _socket = null;
    await socket?.close();
    _reconnecting = false;
    _setState(ProviderWorkerState.stopped);
  }

  void _handleClosed() {
    _socket = null;
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
    _setState(ProviderWorkerState.reconnecting);
    try {
      for (
        var attempt = 0;
        attempt < maxReconnectAttempts && !_stopping;
        attempt++
      ) {
        reconnectAttempts = attempt + 1;
        final multiplier = 1 << attempt;
        await Future<void>.delayed(reconnectDelay * multiplier);
        if (_stopping) return;
        try {
          await _connect();
          return;
        } catch (error) {
          lastError = error;
          _socket = null;
          _setState(ProviderWorkerState.error);
        }
      }
    } finally {
      _reconnecting = false;
      if (_stopping) {
        _setState(ProviderWorkerState.stopped);
      } else if (!isRunning) {
        _setState(ProviderWorkerState.error);
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
    if (metadata['message_type'] != 'notification') return;
    final payload = message['payload'];
    if (payload is! Map) return;
    final subscription = payload['subscription'];
    final event = payload['event'];
    if (subscription is! Map || event is! Map) return;
    final type = subscription['type']?.toString();
    final eventId = switch (type) {
      'channel.chat.message' => 'chat',
      'channel.ban' => event['duration'] == null ? 'ban' : 'timeout',
      'channel.moderate' => event['action'] == 'timeout' ? 'timeout' : null,
      'channel.ad_break.begin' => 'adStarted',
      'channel.channel_points_custom_reward_redemption.add' => 'redemption',
      'channel.cheer' => 'bits',
      'channel.follow' => 'follow',
      'channel.hype_train.begin' => 'hypeTrainStarted',
      'channel.hype_train.progress' => 'hypeTrainLevelUp',
      'channel.hype_train.end' => 'hypeTrainEnded',
      'channel.poll.begin' => 'pollStarted',
      'channel.poll.end' => 'pollEnded',
      'channel.prediction.begin' => 'predictionStarted',
      'channel.prediction.lock' => 'predictionLocked',
      'channel.prediction.end' => 'predictionSettled',
      'channel.subscribe' => 'subscription',
      'channel.subscription.gift' => 'giftedSub',
      'channel.shoutout.create' => 'shoutoutSent',
      'channel.raid' =>
        event['to_broadcaster_user_id']?.toString() == broadcasterId
            ? 'raid'
            : 'raidOut',
      _ => null,
    };
    if (eventId != null) {
      eventHub.emit(eventId, Map<String, dynamic>.from(event));
    }
  }
}

Future<EventSubSocket> _connectSocket(Uri uri) async =>
    WebSocketEventSubSocket(await WebSocket.connect(uri.toString()));
