import 'chat_message.dart';

String? chatImageUrl(Object? value) {
  if (value is! String) return null;
  final uri = Uri.tryParse(value.startsWith('//') ? 'https:$value' : value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443 ||
      !{
        'static-cdn.jtvnw.net',
        'cdn.betterttv.net',
        'cdn.frankerfacez.com',
        'cdn.7tv.app',
        'cdn.7tv.io',
      }.contains(uri.host)) {
    return null;
  }
  return uri.toString();
}

final class ChatEmote {
  const ChatEmote(
    this.name,
    this.text, {
    this.platform,
    this.channelId = '',
    this.provider = 'emoji',
    this.imageUrl,
    this.staticImageUrl,
    this.animated = false,
  });
  final String name, text, provider, channelId;
  final ChatPlatform? platform;
  final String? imageUrl, staticImageUrl;
  final bool animated;
  bool supports(ChatPlatform destination) =>
      platform == null || platform == destination;
  String? image({required bool animate}) => chatImageUrl(
    animate ? imageUrl : staticImageUrl ?? (animated ? null : imageUrl),
  );
  Map<String, dynamic> toJson({required bool animate}) => {
    'name': name,
    'text': text,
    'platform': platform?.name,
    'provider': provider,
    'imageUrl': image(animate: animate),
  };
}

final class ChatTextPart {
  const ChatTextPart(this.text, [this.emote]);
  final String text;
  final ChatEmote? emote;
  Map<String, dynamic> toJson({required bool animate}) => {
    'text': text,
    'imageUrl': ?emote?.image(animate: animate),
  };
}

List<ChatTextPart> chatMessageParts(
  ChatMessage message,
  Iterable<ChatEmote> catalog,
) {
  if (message.deleted) return const [ChatTextPart('Message deleted')];
  final names = <String, ChatEmote>{};
  for (final emote in catalog) {
    if (emote.supports(message.platform) &&
        (emote.channelId.isEmpty || emote.channelId == message.channelId)) {
      names.putIfAbsent(emote.name, () => emote);
    }
  }
  List<ChatTextPart> plain(String text) => [
    for (final token in RegExp(r'\s+|[^\s]+').allMatches(text))
      ChatTextPart(token[0]!, names[token[0]]),
  ];
  final raw = message.source['message'];
  final fragments = raw is Map
      ? raw['fragments']
      : message.source['messageFragments'];
  if (message.platform != ChatPlatform.twitch ||
      fragments is! List ||
      fragments.any((f) => f is! Map || f['text'] is! String) ||
      fragments.map((f) => f['text']).join() != message.text) {
    return plain(message.text);
  }
  return [
    for (final fragment in fragments.cast<Map>())
      ...(() {
        final emote = fragment['emote'];
        final id = emote is Map ? emote['id'] : null;
        if (fragment['type'] == 'emote' &&
            id is String &&
            RegExp(r'^[a-zA-Z0-9_-]{1,128}$').hasMatch(id)) {
          final text = fragment['text'] as String;
          final animated =
              emote['format'] is List &&
              (emote['format'] as List).contains('animated');
          final base = 'https://static-cdn.jtvnw.net/emoticons/v2/$id';
          return [
            ChatTextPart(
              text,
              ChatEmote(
                text,
                text,
                platform: ChatPlatform.twitch,
                provider: 'twitch',
                animated: animated,
                imageUrl: '$base/${animated ? 'animated' : 'static'}/dark/1.0',
                staticImageUrl: '$base/static/dark/1.0',
              ),
            ),
          ];
        }
        return plain(fragment['text'] as String);
      })(),
  ];
}
