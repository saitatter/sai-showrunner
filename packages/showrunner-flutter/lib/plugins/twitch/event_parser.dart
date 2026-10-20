import '../../runtime/expression.dart';

RuntimeMap normalizeTwitchEvent(String eventId, Map event) {
  final normalized = <String, dynamic>{
    ...Map<String, dynamic>.from(event),
    'eventType': eventId,
    'platform': 'twitch',
  };

  void copyIfPresent(String target, Object? value) {
    if (value != null) normalized[target] = value;
  }

  copyIfPresent('viewerId', event['user_id'] ?? event['chatter_user_id']);
  copyIfPresent(
    'viewerName',
    event['user_name'] ?? event['user_login'] ?? event['chatter_user_name'],
  );
  final message = event['message'];
  copyIfPresent('message', message is Map ? message['text'] : message);
  if (message is Map) copyIfPresent('messageFragments', message['fragments']);
  copyIfPresent('messageId', event['message_id']);
  copyIfPresent('bits', event['bits']);
  copyIfPresent('tier', _tierNumber(event['tier']));
  copyIfPresent('totalMonths', event['cumulative_months']);
  copyIfPresent('streakMonths', event['streak_months']);
  copyIfPresent('userInput', event['user_input']);
  copyIfPresent('redemptionId', event['id']);
  copyIfPresent('targetBroadcasterId', event['to_broadcaster_user_id']);
  copyIfPresent('viewers', event['viewers']);

  final badges = event['badges'];
  if (badges is List) {
    normalized['badges'] = badges
        .whereType<Map>()
        .map((badge) => badge['set_id']?.toString() ?? badge['title'])
        .whereType<Object>()
        .join(',');
  }

  final reward = event['reward'];
  if (reward is Map) {
    copyIfPresent('rewardId', reward['id']);
    copyIfPresent('rewardName', reward['title']);
  }

  if (eventId == 'giftedSub') {
    copyIfPresent('gifterId', event['user_id']);
    copyIfPresent('gifterName', event['user_name']);
    copyIfPresent('subs', event['total']);
  }
  return normalized;
}

num? _tierNumber(Object? value) {
  if (value is num) return value;
  final tier = int.tryParse(value?.toString() ?? '');
  if (tier == null) return null;
  return tier ~/ 1000;
}

String? twitchDomainEventType(String? type, Map event, String broadcasterId) {
  return switch (type) {
    'channel.chat.message' => 'chat',
    'channel.chat.message_delete' => 'twitchChatDeleted',
    'channel.chat.clear' => 'twitchChatCleared',
    'channel.chat.clear_user_messages' => 'twitchUserChatCleared',
    'user.whisper.message' => 'twitchWhisper',
    'channel.chat.notification' =>
      event['notice_type'] == 'first_message' ? 'firstTimeChat' : 'chat',
    'channel.ban' =>
      event['is_permanent'] == false || event['ends_at'] != null
          ? 'timeout'
          : 'ban',
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
}
