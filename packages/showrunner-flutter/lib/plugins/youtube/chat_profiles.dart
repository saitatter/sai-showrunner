import '../../runtime/expression.dart';

/// YouTube supplies the public avatar with each live-chat author record.
String? youtubeChatAvatar(RuntimeMap source) {
  final author = source['authorDetails'];
  final url = author is Map ? author['profileImageUrl'] : null;
  if (url is! String || url.length > 2048) return null;
  final uri = Uri.tryParse(url);
  return uri != null &&
          uri.scheme == 'https' &&
          {
            'yt3.ggpht.com',
            'yt4.ggpht.com',
            'yt3.googleusercontent.com',
          }.contains(uri.host) &&
          uri.userInfo.isEmpty &&
          (!uri.hasPort || uri.port == 443)
      ? url
      : null;
}
