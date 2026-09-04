import 'dart:async';

import '../runtime/expression.dart';
import '../schema/viewer_data.dart';
import '../services/plugin_event_hub.dart';
import 'viewer_data_repository.dart';

final class ViewerDataSynchronizer {
  ViewerDataSynchronizer({required this.repository, required this.eventHub});

  final ViewerDataRepository repository;
  final DartPluginEventHub eventHub;
  final _subscriptions = <StreamSubscription<RuntimeMap>>[];

  static const _twitchEvents = <String>{
    'chat',
    'ban',
    'timeout',
    'follow',
    'subscription',
    'giftedSub',
    'redemption',
    'bits',
  };

  static const _youtubeEvents = <String>{
    'chatMessage',
    'superChat',
    'membership',
  };

  bool get isRunning => _subscriptions.isNotEmpty;

  Future<void> start() async {
    if (isRunning) return;
    for (final eventId in [..._twitchEvents, ..._youtubeEvents]) {
      _subscriptions.add(
        eventHub.stream(eventId).listen((event) {
          unawaited(_handleEvent(eventId, event));
        }),
      );
    }
  }

  Future<void> stop() async {
    final subscriptions = List<StreamSubscription<RuntimeMap>>.from(
      _subscriptions,
    );
    _subscriptions.clear();
    await Future.wait(
      subscriptions.map((subscription) => subscription.cancel()),
    );
  }

  Future<ViewerDataSyncResult?> syncEvent(
    String eventId,
    RuntimeMap event,
  ) async {
    final identity = _identityForEvent(eventId, event);
    if (identity == null) return null;
    final provider = _twitchEvents.contains(eventId) ? 'twitch' : 'youtube';
    final result = await repository.syncViewerIdentity(provider, identity);
    if (!result.changed) return result;

    final payload = <String, dynamic>{
      'provider': provider,
      'id': result.row.viewer.id,
      'displayName': result.row.viewer.displayName,
      'values': result.row.values,
    };
    eventHub.emit(
      result.created ? 'viewerDataAdded' : 'viewerDataChanged',
      payload,
    );
    return result;
  }

  Future<void> _handleEvent(String eventId, RuntimeMap event) async {
    try {
      await syncEvent(eventId, event);
    } catch (_) {
      // Provider events must not take down the worker when a local definition
      // or a malformed legacy row cannot be synchronized.
    }
  }

  ViewerIdentity? _identityForEvent(String eventId, RuntimeMap event) {
    if (_twitchEvents.contains(eventId)) {
      if (_isAnonymous(event)) return null;
      final id = _firstText([
        event['chatter_user_id'],
        event['user_id'],
        event['viewerId'],
      ]);
      if (id == null) return null;
      final displayName =
          _firstText([
            event['chatter_user_name'],
            event['user_name'],
            event['chatter_user_login'],
            event['user_login'],
          ]) ??
          id;
      return ViewerIdentity(id: id, displayName: displayName);
    }
    if (_youtubeEvents.contains(eventId)) {
      final author = event['authorDetails'];
      final authorMap = author is Map
          ? Map<String, dynamic>.from(author)
          : const <String, dynamic>{};
      final id = _firstText([
        authorMap['channelId'],
        event['authorChannelId'],
        event['user_id'],
      ]);
      if (id == null) return null;
      final displayName =
          _firstText([
            authorMap['displayName'],
            authorMap['channelTitle'],
            event['authorName'],
          ]) ??
          id;
      return ViewerIdentity(id: id, displayName: displayName);
    }
    return null;
  }

  bool _isAnonymous(RuntimeMap event) {
    final value = event['is_anonymous'] ?? event['isAnonymous'];
    return value == true || value?.toString().toLowerCase() == 'true';
  }
}

String? _firstText(Iterable<dynamic> values) {
  for (final value in values) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty) return text;
  }
  return null;
}
