import '../../schema/resource.dart';

/// Public, presentation-only entries supplied by application-owned chat. This
/// port has no command execution, provider source payloads or credentials.
final class OverlayChatEntry {
  const OverlayChatEntry({
    required this.id,
    required this.platform,
    required this.displayName,
    required this.message,
    required this.receivedAt,
    this.badges = const [],
  });
  final String id, platform, displayName, message;
  final DateTime receivedAt;
  final List<String> badges;
}

typedef OverlayChatReader = List<OverlayChatEntry> Function();
typedef ReadOverlayChat = Future<List<OverlayChatEntry>> Function();

final class OverlayChatNotEnabled implements Exception {
  const OverlayChatNotEnabled();
}

final class OverlayChatProjection {
  OverlayChatProjection._(
    this.limit,
    this.lifetime,
    this.platform,
    this.showBadges,
  );
  final int limit;
  final Duration lifetime;
  final String platform;
  final bool showBadges;

  factory OverlayChatProjection.fromResource(
    ResourceData resource,
    String widgetId,
  ) {
    final widgets = resource.config['widgets'];
    if (widgets is! List || widgets.length > 256) {
      throw const FormatException('Invalid overlay widgets.');
    }
    final matches = widgets
        .whereType<Map>()
        .where((w) => w['id'] == widgetId)
        .toList();
    if (matches.length != 1) throw const OverlayChatNotEnabled();
    final widget = matches.single;
    final config = widget['config'];
    if (widget['plugin'] != 'overlays' ||
        widget['widget'] != 'chatFeed' ||
        config is! Map ||
        config['source'] != 'unifiedChat') {
      throw const OverlayChatNotEnabled();
    }
    final limit = config['maxMessages'] ?? 8;
    final seconds = config['fadeTime'] ?? 10;
    final platform = config['platform'] ?? 'all';
    final badges = config['showBadges'] ?? true;
    if (limit is! num ||
        !limit.isFinite ||
        limit != limit.roundToDouble() ||
        limit < 1 ||
        limit > 200 ||
        seconds is! num ||
        !seconds.isFinite ||
        seconds < 0 ||
        seconds > 86400 ||
        !{'all', 'twitch', 'youtube', 'kick'}.contains(platform) ||
        badges is! bool) {
      throw const FormatException('Invalid unified chat configuration.');
    }
    return OverlayChatProjection._(
      limit.toInt(),
      Duration(milliseconds: (seconds * 1000).round()),
      platform as String,
      badges,
    );
  }

  Map<String, Object?> project(List<OverlayChatEntry> history, DateTime now) {
    final rows = <Map<String, Object?>>[];
    final ids = <String>{};
    for (final entry in history.reversed.take(500)) {
      if (!{'twitch', 'youtube', 'kick'}.contains(entry.platform) ||
          (platform != 'all' && entry.platform != platform)) {
        continue;
      }
      final expiry = entry.receivedAt.add(lifetime);
      if (lifetime != Duration.zero && !expiry.isAfter(now)) continue;
      if (entry.id.isEmpty ||
          entry.id.runes.length > 512 ||
          !ids.add(entry.id)) {
        continue;
      }
      rows.add({
        'id': _text(entry.id, 512),
        'platform': entry.platform,
        'displayName': _text(entry.displayName, 256),
        'message': _text(entry.message, 4096),
        if (showBadges)
          'badges': entry.badges.take(8).map((b) => _text(b, 64)).toList(),
        if (lifetime != Duration.zero)
          'expiresInMs': expiry
              .difference(now)
              .inMilliseconds
              .clamp(0, lifetime.inMilliseconds),
      });
      if (rows.length == limit) break;
    }
    return {'version': 1, 'messages': rows};
  }

  static String _text(String value, int max) =>
      String.fromCharCodes(value.runes.take(max));
}
