import '../../runtime/expression.dart';
import '../../schema/resource.dart';
import 'actions.dart';
import 'contracts.dart';

/// Sender identity follows the credential, never a caller-supplied sender ID.
/// A missing/expired bot grant fails explicitly; it cannot fall back to channel.
final class TwitchChatAccountRouter {
  const TwitchChatAccountRouter({
    required this.broadcasterId,
    required this.channelRequest,
    required this.loadBot,
    required this.botRequest,
  });
  final String broadcasterId;
  final TwitchRequest channelRequest;
  final Future<ResourceData?> Function() loadBot;
  final TwitchRequest Function(String token) botRequest;

  Future<RuntimeMap> send(TwitchChatAccount account, RuntimeMap body) async {
    final target = body['broadcaster_id'];
    final channel = target is String && target.isNotEmpty
        ? target
        : broadcasterId;
    if (channel.isEmpty) {
      throw StateError('Connect a Twitch channel before sending.');
    }
    if (account == TwitchChatAccount.broadcaster) {
      if (broadcasterId.isEmpty) {
        throw StateError('Connect a Twitch broadcaster account.');
      }
      return channelRequest('POST', '/helix/chat/messages', {}, {
        ...body,
        'broadcaster_id': channel,
        'sender_id': broadcasterId,
      });
    }
    final bot = await loadBot();
    final token = bot?.config['accessToken'];
    final botId = bot?.config['twitchId'];
    if (token is! String ||
        token.isEmpty ||
        botId is! String ||
        botId.isEmpty) {
      throw StateError('Connect a Twitch bot account before sending as bot.');
    }
    final expiry = bot?.config['expiresAt'];
    if (expiry is String &&
        (DateTime.tryParse(expiry)?.isBefore(DateTime.now()) ?? true)) {
      throw StateError('Reauthorize the Twitch bot account before sending.');
    }
    return botRequest(token)('POST', '/helix/chat/messages', {}, {
      ...body,
      'broadcaster_id': channel,
      'sender_id': botId,
    });
  }
}
