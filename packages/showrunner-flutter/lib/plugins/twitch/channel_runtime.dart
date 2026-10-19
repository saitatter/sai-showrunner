import '../../runtime/expression.dart';
import '../../services/http_provider_transports.dart';
import '../../services/showrunner_data_service.dart';
import 'account_runtime.dart';

typedef TwitchChannelRequest =
    Future<RuntimeMap> Function(
      String method,
      String path,
      RuntimeMap query,
      dynamic body,
    );

final class TwitchChannelSnapshot {
  const TwitchChannelSnapshot({
    required this.broadcasterId,
    required this.broadcasterName,
    required this.channelTitle,
    required this.categoryId,
    required this.categoryName,
    required this.tags,
    required this.isLive,
    required this.viewerCount,
    required this.startedAt,
    this.profileImageUrl,
    this.viewCount,
  });

  final String broadcasterId;
  final String broadcasterName;
  final String channelTitle;
  final String categoryId;
  final String categoryName;
  final List<String> tags;
  final bool isLive;
  final int? viewerCount;
  final DateTime? startedAt;
  final String? profileImageUrl;
  final int? viewCount;
}

final class TwitchChannelInfoService {
  TwitchChannelInfoService({required this.dataService, this.request});

  final ShowRunnerDataService dataService;
  final TwitchChannelRequest? request;

  Future<TwitchChannelSnapshot> load() async {
    final settings = await loadTwitchChannelSettings(dataService);
    final token = settings['accessToken']?.toString().trim() ?? '';
    final clientId = settings['clientId']?.toString().trim() ?? '';
    final broadcasterId = settings['broadcasterId']?.toString().trim() ?? '';
    if (token.isEmpty || clientId.isEmpty || broadcasterId.isEmpty) {
      throw StateError(
        'Twitch access token, client ID, and broadcaster ID are required.',
      );
    }
    final fetch =
        request ??
        JsonHttpTransport(
          baseUrl: 'https://api.twitch.tv',
          accessToken: token,
          headers: {'Client-Id': clientId},
        ).request;
    final responses = await Future.wait([
      fetch('GET', '/helix/users', {'id': broadcasterId}, null),
      fetch('GET', '/helix/channels', {'broadcaster_id': broadcasterId}, null),
      fetch('GET', '/helix/streams', {'user_id': broadcasterId}, null),
    ]);
    final user = _first(responses[0]);
    final channel = _first(responses[1]);
    final stream = _first(responses[2]);
    final streamType = stream?['type']?.toString() ?? '';
    return TwitchChannelSnapshot(
      broadcasterId: broadcasterId,
      broadcasterName: _text(
        user?['display_name'] ?? channel?['broadcaster_name'],
      ),
      channelTitle: _text(channel?['title']),
      categoryId: _text(channel?['game_id']),
      categoryName: _text(channel?['game_name']),
      tags: _strings(channel?['tags']),
      isLive: streamType == 'live',
      viewerCount: _int(stream?['viewer_count']),
      startedAt: DateTime.tryParse(_text(stream?['started_at'])),
      profileImageUrl: _optionalText(user?['profile_image_url']),
      viewCount: _int(user?['view_count']),
    );
  }
}

RuntimeMap? _first(RuntimeMap response) {
  final data = response['data'];
  if (data is List && data.isNotEmpty && data.first is Map) {
    return Map<String, dynamic>.from(data.first as Map);
  }
  return null;
}

String _text(Object? value) => value?.toString() ?? '';

String? _optionalText(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

int? _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value');

List<String> _strings(Object? value) => value is List
    ? value
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList()
    : const [];
