import '../../runtime/expression.dart';

enum ChatPlatform { twitch, youtube }

enum ChatOrigin {
  chat,
  sharedChat,
  whisper,
  botWhisper,
  subscription,
  internal,
}

enum ChatPermission { everyone, subscriber, vip, moderator, broadcaster }

final class ChatMessage {
  ChatMessage({
    required this.platform,
    required this.id,
    required this.channelId,
    required this.userId,
    required this.userName,
    required this.text,
    required this.receivedAt,
    this.origin = ChatOrigin.chat,
    this.isModerator = false,
    this.isSubscriber = false,
    this.isVip = false,
    this.isBroadcaster = false,
    this.isBot = false,
    this.deleted = false,
    Map<String, dynamic> source = const {},
  }) : source = Map.unmodifiable(source);

  final ChatPlatform platform;
  final ChatOrigin origin;
  final String id;
  final String channelId;
  final String userId;
  final String userName;
  final String text;
  final DateTime receivedAt;
  final bool isModerator, isSubscriber, isVip, isBroadcaster, isBot, deleted;
  final Map<String, dynamic> source;

  String get identity => '${platform.name}:$channelId:$id';
  String get userIdentity => '${platform.name}:$userId';

  bool permits(ChatPermission permission) => switch (permission) {
    ChatPermission.everyone => true,
    ChatPermission.broadcaster => isBroadcaster,
    ChatPermission.moderator => isBroadcaster || isModerator,
    ChatPermission.subscriber => isBroadcaster || isModerator || isSubscriber,
    ChatPermission.vip => isBroadcaster || isModerator || isVip,
  };

  RuntimeMap get context => {
    'platform': platform.name,
    'origin': origin.name,
    'viewerId': userId,
    'viewerName': userName,
    'messageId': id,
    'message': text,
    'channelId': channelId,
    if (platform == ChatPlatform.youtube) 'liveChatId': channelId,
    if (platform == ChatPlatform.twitch) 'broadcasterId': channelId,
    'isModerator': isModerator,
    'isMember': isSubscriber,
    'isOwner': isBroadcaster,
  };

  ChatMessage markDeleted() => ChatMessage(
    platform: platform,
    id: id,
    channelId: channelId,
    userId: userId,
    userName: userName,
    text: text,
    receivedAt: receivedAt,
    origin: origin,
    isModerator: isModerator,
    isSubscriber: isSubscriber,
    isVip: isVip,
    isBroadcaster: isBroadcaster,
    isBot: isBot,
    deleted: true,
    source: source,
  );

  static ChatMessage? fromTwitch(
    RuntimeMap event, {
    DateTime? now,
    Set<String> botIds = const {},
    ChatOrigin? origin,
  }) {
    final message = event['message'];
    final text = message is Map ? message['text'] : message;
    if (text is! String || text.isEmpty) return null;
    final userId = (event['chatter_user_id'] ?? event['viewerId'] ?? '')
        .toString();
    final channelId =
        (event['broadcaster_user_id'] ?? event['broadcasterId'] ?? '')
            .toString();
    final badges = event['badges'];
    final names = badges is List
        ? badges.whereType<Map>().map((b) => b['set_id']?.toString()).toSet()
        : (badges?.toString() ?? '').split(',').toSet();
    return ChatMessage(
      platform: ChatPlatform.twitch,
      origin:
          origin ??
          (event['source_broadcaster_user_id'] != null &&
                  event['source_broadcaster_user_id'] != channelId
              ? ChatOrigin.sharedChat
              : ['sub', 'resub'].contains(event['notice_type'])
              ? ChatOrigin.subscription
              : ChatOrigin.chat),
      id: (event['message_id'] ?? event['messageId'] ?? '').toString(),
      channelId: channelId,
      userId: userId,
      userName: (event['chatter_user_name'] ?? event['viewerName'] ?? userId)
          .toString(),
      text: text,
      receivedAt: now ?? DateTime.now(),
      isModerator: names.contains('moderator'),
      isSubscriber: names.contains('subscriber') || names.contains('founder'),
      isVip: names.contains('vip'),
      isBroadcaster:
          names.contains('broadcaster') ||
          (channelId.isNotEmpty && channelId == userId),
      isBot: botIds.contains(userId),
      source: event,
    );
  }

  static ChatMessage? fromYouTube(
    RuntimeMap event, {
    DateTime? now,
    Set<String> botIds = const {},
    String liveChatId = '',
  }) {
    final snippet = event['snippet'];
    final author = event['authorDetails'];
    if (snippet is! Map || author is! Map) return null;
    final type = snippet['type'];
    if (type != null &&
        type != 'textMessageEvent' &&
        type != 'superChatEvent' &&
        type != 'superStickerEvent') {
      return null;
    }
    final text = snippet['displayMessage'];
    if (text is! String || text.isEmpty) return null;
    final userId = (author['channelId'] ?? snippet['authorChannelId'] ?? '')
        .toString();
    return ChatMessage(
      platform: ChatPlatform.youtube,
      id: (event['id'] ?? '').toString(),
      channelId: (snippet['liveChatId'] ?? liveChatId).toString(),
      userId: userId,
      userName: (author['displayName'] ?? userId).toString(),
      text: text,
      receivedAt: now ?? DateTime.now(),
      isModerator: author['isChatModerator'] == true,
      isSubscriber: author['isChatSponsor'] == true,
      isBroadcaster: author['isChatOwner'] == true,
      isBot: botIds.contains(userId),
      source: event,
    );
  }
}
