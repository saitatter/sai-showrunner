import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../runtime/expression.dart';
import '../../services/plugin_event_hub.dart';
import '../runtime/provider_worker_status.dart';
import 'actions.dart';

typedef EventSubSocketFactory = Future<EventSubSocket> Function(Uri uri);

abstract interface class EventSubSocket {
  Stream<dynamic> get messages;

  Future<void> close([int? code, String? reason]);
}

final class TwitchEventSubSubscription {
  const TwitchEventSubSubscription({
    required this.type,
    required this.version,
    required this.condition,
  });

  final String type;
  final String version;
  final RuntimeMap condition;
}

List<TwitchEventSubSubscription> defaultTwitchEventSubSubscriptions(
  String broadcasterId,
) => [
  TwitchEventSubSubscription(
    type: 'channel.chat.message',
    version: '1',
    condition: {'broadcaster_user_id': broadcasterId, 'user_id': broadcasterId},
  ),
  TwitchEventSubSubscription(
    type: 'channel.chat.notification',
    version: '1',
    condition: {'broadcaster_user_id': broadcasterId, 'user_id': broadcasterId},
  ),
  TwitchEventSubSubscription(
    type: 'channel.ban',
    version: '1',
    condition: {
      'broadcaster_user_id': broadcasterId,
      'moderator_user_id': broadcasterId,
    },
  ),
  TwitchEventSubSubscription(
    type: 'channel.moderate',
    version: '2',
    condition: {
      'broadcaster_user_id': broadcasterId,
      'moderator_user_id': broadcasterId,
    },
  ),
  for (final type in const [
    'channel.ad_break.begin',
    'channel.ad_break.end',
    'channel.ad_schedule',
    'channel.channel_points_custom_reward_redemption.add',
    'channel.cheer',
    'channel.hype_train.begin',
    'channel.hype_train.progress',
    'channel.hype_train.end',
    'channel.poll.begin',
    'channel.poll.end',
    'channel.prediction.begin',
    'channel.prediction.lock',
    'channel.prediction.end',
    'channel.subscribe',
    'channel.subscription.gift',
  ])
    TwitchEventSubSubscription(
      type: type,
      version: type.startsWith('channel.hype_train') ? '2' : '1',
      condition: {'broadcaster_user_id': broadcasterId},
    ),
  TwitchEventSubSubscription(
    type: 'channel.follow',
    version: '2',
    condition: {
      'broadcaster_user_id': broadcasterId,
      'moderator_user_id': broadcasterId,
    },
  ),
  TwitchEventSubSubscription(
    type: 'channel.shoutout.create',
    version: '1',
    condition: {
      'broadcaster_user_id': broadcasterId,
      'moderator_user_id': broadcasterId,
    },
  ),
  TwitchEventSubSubscription(
    type: 'channel.shoutout.receive',
    version: '1',
    condition: {'broadcaster_user_id': broadcasterId},
  ),
  TwitchEventSubSubscription(
    type: 'channel.raid',
    version: '1',
    condition: {'to_broadcaster_user_id': broadcasterId},
  ),
  TwitchEventSubSubscription(
    type: 'channel.raid',
    version: '1',
    condition: {'from_broadcaster_user_id': broadcasterId},
  ),
];

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
    List<String>? subscriptionTypes,
    List<TwitchEventSubSubscription>? subscriptions,
    this.ignoreSubscriptionErrors = true,
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

  ProviderWorkerState get state => _state;
  bool get isRunning => _state == ProviderWorkerState.running;
  bool get isReconnecting => _state == ProviderWorkerState.reconnecting;

  List<String> get subscriptionTypes =>
      _subscriptions.map((subscription) => subscription.type).toList();

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
    final subscriptionErrors = <String>[];
    for (final subscriptionRequest in _subscriptions) {
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
    this.subscriptionErrors = List.unmodifiable(subscriptionErrors);
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
      'channel.chat.notification' =>
        event['notice_type'] == 'first_message' ? 'firstTimeChat' : 'chat',
      'channel.ban' => event['duration'] == null ? 'ban' : 'timeout',
      'channel.moderate' => event['action'] == 'timeout' ? 'timeout' : null,
      'channel.ad_break.begin' => 'adStarted',
      'channel.ad_break.end' => 'adEnded',
      'channel.ad_schedule' => 'adSchedule',
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
      'channel.shoutout.receive' => 'shoutoutReceived',
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
