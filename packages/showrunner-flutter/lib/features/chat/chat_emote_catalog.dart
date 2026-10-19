import '../../services/http_provider_transports.dart';
import 'chat_emote.dart';
import 'chat_message.dart';

typedef ChatCatalogGet = Future<Object?> Function(Uri uri);
typedef TwitchCatalogGet =
    Future<Map<String, dynamic>> Function(
      String path,
      Map<String, dynamic> query,
    );

final class ChatEmoteCatalog {
  ChatEmoteCatalog({ChatCatalogGet? get, DateTime Function()? now})
    : get = get ?? _get,
      now = now ?? DateTime.now;
  final ChatCatalogGet get;
  final DateTime Function() now;
  final _cache = <String, (DateTime, Object?)>{};
  final status = <String, String>{};
  static Future<Object?> _get(Uri uri) => JsonHttpTransport(
    baseUrl: uri.origin,
    timeout: const Duration(seconds: 5),
    maxRetries: 0,
  ).requestValue('GET', uri.path, uri.queryParameters, null);
  Future<Object?> _cached(String url) async {
    final cached = _cache[url];
    if (cached != null &&
        now().difference(cached.$1) < const Duration(minutes: 15)) {
      return cached.$2;
    }
    final result = await get(Uri.parse(url));
    if (_cache.length >= 32) _cache.remove(_cache.keys.first);
    _cache[url] = (now(), result);
    return result;
  }

  Future<List<ChatEmote>> load(
    ChatPlatform platform,
    String channel, {
    TwitchCatalogGet? twitch,
  }) async {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(channel)) {
      throw const FormatException('Connect a channel before loading emotes.');
    }
    status.clear();
    if (platform == ChatPlatform.twitch && twitch == null) {
      status['Twitch channel'] = 'unavailable';
      status['Twitch global'] = 'unavailable';
    }
    final results = await Future.wait([
      if (platform == ChatPlatform.twitch && twitch != null)
        for (final local in [true, false])
          _source('Twitch ${local ? 'channel' : 'global'}', () async {
            final json = await twitch(
              local ? '/helix/chat/emotes' : '/helix/chat/emotes/global',
              local ? {'broadcaster_id': channel} : {},
            );
            return parseTwitchEmotes(json, channelId: local ? channel : '');
          }),
      for (final local in [true, false])
        _source('7TV ${local ? 'channel' : 'global'}', () async {
          final json = await _cached(
            local
                ? 'https://7tv.io/v3/users/${platform.name}/$channel'
                : 'https://7tv.io/v3/emote-sets/global',
          );
          return parseSevenTvEmotes(
            json,
            platform: platform,
            channelId: local ? channel : '',
          );
        }),
      for (final local in [true, false])
        _source('BTTV ${local ? 'channel' : 'global'}', () async {
          final json = await _cached(
            local
                ? 'https://api.betterttv.net/3/cached/users/${platform.name}/$channel'
                : 'https://api.betterttv.net/3/cached/emotes/global',
          );
          return parseBttvEmotes(
            json,
            platform: platform,
            channelId: local ? channel : '',
          );
        }),
      if (platform == ChatPlatform.twitch)
        for (final local in [true, false])
          _source('FFZ ${local ? 'channel' : 'global'}', () async {
            final json = await _cached(
              local
                  ? 'https://api.frankerfacez.com/v1/room/id/$channel'
                  : 'https://api.frankerfacez.com/v1/set/global',
            );
            return parseFfzEmotes(json, channelId: local ? channel : '');
          }),
    ]);
    // Native fragments win, then Twitch > 7TV > BTTV > FFZ; channel beats global.
    return results.expand((list) => list).take(10000).toList();
  }

  Future<List<ChatEmote>> _source(
    String name,
    Future<List<ChatEmote>> Function() read,
  ) async {
    try {
      final result = await read();
      status[name] = '${result.length} loaded';
      return result;
    } catch (_) {
      status[name] = 'unavailable';
      return [];
    }
  }
}

List<Map> _items(Object? value) =>
    value is List ? value.whereType<Map>().toList() : [];
List<ChatEmote> parseTwitchEmotes(
  Map<String, dynamic> json, {
  String channelId = '',
}) => [
  for (final item in _items(json['data']))
    ...(() {
      final name = item['name'], id = item['id'];
      if (name is! String ||
          id is! String ||
          !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id)) {
        return <ChatEmote>[];
      }
      final animated =
          item['format'] is List &&
          (item['format'] as List).contains('animated');
      final base = 'https://static-cdn.jtvnw.net/emoticons/v2/$id';
      return [
        ChatEmote(
          name,
          name,
          platform: ChatPlatform.twitch,
          provider: 'twitch',
          channelId: channelId,
          animated: animated,
          imageUrl: '$base/${animated ? 'animated' : 'static'}/dark/1.0',
          staticImageUrl: '$base/static/dark/1.0',
        ),
      ];
    })(),
];

List<ChatEmote> parseBttvEmotes(
  Object? json, {
  required ChatPlatform platform,
  String channelId = '',
}) {
  final items = json is Map
      ? [..._items(json['channelEmotes']), ..._items(json['sharedEmotes'])]
      : _items(json);
  return [
    for (final item in items)
      ...(() {
        final id = item['id'], name = item['code'];
        if (id is! String ||
            name is! String ||
            !RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id)) {
          return <ChatEmote>[];
        }
        final url = 'https://cdn.betterttv.net/emote/$id/1x';
        return [
          ChatEmote(
            name,
            name,
            platform: platform,
            provider: 'bttv',
            channelId: channelId,
            imageUrl: url,
            staticImageUrl: item['imageType'] == 'png' ? url : null,
            animated: item['imageType'] != 'png',
          ),
        ];
      })(),
  ];
}

List<ChatEmote> parseFfzEmotes(Object? json, {String channelId = ''}) {
  final sets = json is Map ? json['sets'] : null;
  if (sets is! Map) return [];
  final defaults = json is Map ? json['default_sets'] : null;
  return [
    for (final entry in sets.entries)
      if (channelId.isNotEmpty ||
          defaults is! List ||
          defaults.any((id) => '$id' == '${entry.key}'))
        for (final item in _items(
          entry.value is Map ? entry.value['emoticons'] : null,
        ))
          ...(() {
            final name = item['name'],
                urls = item['urls'],
                animated = item['animated'];
            if (name is! String || urls is! Map) return <ChatEmote>[];
            final staticUrl = chatImageUrl(urls['1']);
            final animatedUrl = animated is Map
                ? chatImageUrl(animated['1'])
                : null;
            return [
              ChatEmote(
                name,
                name,
                platform: ChatPlatform.twitch,
                provider: 'ffz',
                channelId: channelId,
                imageUrl: animatedUrl ?? staticUrl,
                staticImageUrl: staticUrl,
                animated: animatedUrl != null,
              ),
            ];
          })(),
  ];
}

List<ChatEmote> parseSevenTvEmotes(
  Object? json, {
  required ChatPlatform platform,
  String channelId = '',
}) {
  if (json is! Map) return [];
  final set = json['emote_set'] is Map ? json['emote_set'] as Map : json;
  return [
    for (final item in _items(set['emotes']))
      ...(() {
        final name = item['name'], data = item['data'];
        final host = data is Map ? data['host'] : null;
        if (name is! String || host is! Map || host['url'] is! String) {
          return <ChatEmote>[];
        }
        final files = _items(host['files']);
        String? fileUrl(bool static) {
          final file = files
              .where(
                (f) =>
                    f['name'] is String &&
                    (f['name'] as String).endsWith('.webp') &&
                    ((f['name'] as String).contains('_static') == static),
              )
              .firstOrNull;
          return file == null
              ? null
              : chatImageUrl('${host['url']}/${file['name']}');
        }

        final animated = data is Map && data['animated'] == true;
        final url = fileUrl(false) ?? fileUrl(true);
        return [
          ChatEmote(
            name,
            name,
            platform: platform,
            provider: '7tv',
            channelId: channelId,
            imageUrl: url,
            staticImageUrl: fileUrl(true) ?? (animated ? null : url),
            animated: animated,
          ),
        ];
      })(),
  ];
}
