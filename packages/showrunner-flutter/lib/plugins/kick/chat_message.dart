import '../../features/chat/chat_message.dart';
import '../../runtime/expression.dart';

ChatMessage? kickChatMessage(RuntimeMap event) {
  final id = event['messageId'];
  final channel = event['broadcasterId'];
  final user = event['viewerId'];
  final name = event['viewerName'];
  final text = event['message'];
  final time = event['createdAt'];
  if (id is! String ||
      id.isEmpty ||
      channel is! String ||
      channel.isEmpty ||
      user is! String ||
      user.isEmpty ||
      name is! String ||
      text is! String ||
      time is! String) {
    return null;
  }
  final createdAt = DateTime.tryParse(time);
  if (createdAt == null) return null;
  return ChatMessage(
    platform: ChatPlatform.kick,
    id: id,
    channelId: channel,
    userId: user,
    userName: name,
    text: text,
    receivedAt: DateTime.now(),
    isBroadcaster: event['isOwner'] == true,
    isModerator: event['isModerator'] == true,
    isSubscriber: event['isSubscriber'] == true,
    isVip: event['isVip'] == true,
    isBot: event['isBot'] == true,
    source: {...event, 'providerTime': createdAt.toUtc().toIso8601String()},
  );
}

String? kickChatAvatar(RuntimeMap source) {
  final value = source['avatarUrl'];
  if (value is! String || value.length > 2048) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443 ||
      !const {'kick.com', 'files.kick.com'}.contains(uri.host)) {
    return null;
  }
  return value;
}
