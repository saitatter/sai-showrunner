import '../../runtime/expression.dart';

final class TwitchEventSubSubscription {
  const TwitchEventSubSubscription({
    required this.type,
    required this.version,
    required this.condition,
  });

  final String type;
  final String version;
  final RuntimeMap condition;
}

List<TwitchEventSubSubscription> defaultTwitchEventSubSubscriptions(
  String broadcasterId,
) => [
  TwitchEventSubSubscription(
    type: 'channel.chat.message',
    version: '1',
    condition: {'broadcaster_user_id': broadcasterId, 'user_id': broadcasterId},
  ),
  for (final type in [
    'channel.chat.message_delete',
    'channel.chat.clear',
    'channel.chat.clear_user_messages',
  ])
    TwitchEventSubSubscription(
      type: type,
      version: '1',
      condition: {
        'broadcaster_user_id': broadcasterId,
        'user_id': broadcasterId,
      },
    ),
  TwitchEventSubSubscription(
    type: 'user.whisper.message',
    version: '1',
    condition: {'user_id': broadcasterId},
  ),
  TwitchEventSubSubscription(
    type: 'channel.chat.notification',
    version: '1',
    condition: {'broadcaster_user_id': broadcasterId, 'user_id': broadcasterId},
  ),
  TwitchEventSubSubscription(
    type: 'channel.ban',
    version: '1',
    condition: {'broadcaster_user_id': broadcasterId},
  ),
  for (final type in const [
    'channel.ad_break.begin',
    'channel.channel_points_custom_reward_redemption.add',
    'channel.cheer',
    'channel.hype_train.begin',
    'channel.hype_train.progress',
    'channel.hype_train.end',
    'channel.poll.begin',
    'channel.poll.end',
    'channel.prediction.begin',
    'channel.prediction.lock',
    'channel.prediction.end',
    'channel.subscribe',
    'channel.subscription.gift',
  ])
    TwitchEventSubSubscription(
      type: type,
      version: type.startsWith('channel.hype_train') ? '2' : '1',
      condition: {'broadcaster_user_id': broadcasterId},
    ),
  TwitchEventSubSubscription(
    type: 'channel.follow',
    version: '2',
    condition: {
      'broadcaster_user_id': broadcasterId,
      'moderator_user_id': broadcasterId,
    },
  ),
  TwitchEventSubSubscription(
    type: 'channel.shoutout.create',
    version: '1',
    condition: {
      'broadcaster_user_id': broadcasterId,
      'moderator_user_id': broadcasterId,
    },
  ),
  TwitchEventSubSubscription(
    type: 'channel.shoutout.receive',
    version: '1',
    condition: {
      'broadcaster_user_id': broadcasterId,
      'moderator_user_id': broadcasterId,
    },
  ),
  TwitchEventSubSubscription(
    type: 'channel.raid',
    version: '1',
    condition: {'to_broadcaster_user_id': broadcasterId},
  ),
  TwitchEventSubSubscription(
    type: 'channel.raid',
    version: '1',
    condition: {'from_broadcaster_user_id': broadcasterId},
  ),
];
