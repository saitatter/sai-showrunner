import '../../runtime/expression.dart';

RuntimeMap flattenYouTubeEvent(Map<String, dynamic> item, {String? eventType}) {
  final snippet = item['snippet'] is Map
      ? Map<String, dynamic>.from(item['snippet'] as Map)
      : const <String, dynamic>{};
  final author = item['authorDetails'] is Map
      ? Map<String, dynamic>.from(item['authorDetails'] as Map)
      : const <String, dynamic>{};
  final superChat = snippet['superChatDetails'] is Map
      ? Map<String, dynamic>.from(snippet['superChatDetails'] as Map)
      : const <String, dynamic>{};
  final superSticker = snippet['superStickerDetails'] is Map
      ? Map<String, dynamic>.from(snippet['superStickerDetails'] as Map)
      : const <String, dynamic>{};
  final membership = snippet['newSponsorDetails'] is Map
      ? Map<String, dynamic>.from(snippet['newSponsorDetails'] as Map)
      : const <String, dynamic>{};
  final textDetails = snippet['textMessageDetails'] is Map
      ? Map<String, dynamic>.from(snippet['textMessageDetails'] as Map)
      : const <String, dynamic>{};
  final message =
      textDetails['messageText'] ??
      superChat['userComment'] ??
      superSticker['userComment'] ??
      membership['memberLevelName'] ??
      '';
  final normalized = <String, dynamic>{
    'viewerId': author['channelId'] ?? '',
    'viewerName': author['displayName'] ?? '',
    'message': message,
    'messageId': item['id'] ?? '',
    'avatarUrl': author['profileImageUrl'] ?? '',
    'isModerator': author['isChatModerator'] == true,
    'isMember': author['isChatSponsor'] == true,
    'isOwner': author['isChatOwner'] == true,
  };
  void addIfPresent(String key, dynamic value) {
    if (value != null) normalized[key] = value;
  }

  addIfPresent('amountMicros', superChat['amountMicros']);
  addIfPresent('currency', superChat['currency']);
  addIfPresent('amountMicros', superSticker['amountMicros']);
  addIfPresent('currency', superSticker['currency']);
  addIfPresent('eventType', eventType);
  addIfPresent('memberLevelName', membership['memberLevelName']);
  addIfPresent('memberMonth', membership['memberMonth']);

  return {...item, ...normalized};
}

String youTubeDomainEventType(String? type) {
  return switch (type) {
    'superChatEvent' => 'superChat',
    'superStickerEvent' => 'superSticker',
    'memberMilestoneChatEvent' || 'newSponsorEvent' => 'membership',
    _ => 'chatMessage',
  };
}
