import 'dart:convert';

import 'package:characters/characters.dart';

import '../../runtime/expression.dart';

/// Kick IDs are positive integers on the wire; viewer identities use strings.
int kickUserId(Object? value, String field) {
  final parsed = switch (value) {
    int number => number,
    String text when RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(text) =>
      int.tryParse(text),
    _ => null,
  };
  if (parsed == null || parsed <= 0 || parsed > 9223372036854775807) {
    throw ArgumentError('$field must be a positive integer ID.');
  }
  return parsed;
}

String kickMessageId(Object? value) {
  if (value is! String || !RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value)) {
    throw ArgumentError('messageId must be a valid message ID.');
  }
  return value;
}

String validateKickMessage(Object? value) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.characters.length > 500 ||
      utf8.encode(value).length > 2048) {
    throw ArgumentError(
      'message must contain 1 to 500 visible characters and at most 2048 UTF-8 bytes.',
    );
  }
  return value;
}

enum KickChatAccount { user, bot }

final class KickSendChatConfig {
  KickSendChatConfig.fromRuntime(RuntimeMap value)
    : message = validateKickMessage(value['message']),
      broadcasterId = value['broadcasterId'] == null
          ? null
          : kickUserId(value['broadcasterId'], 'broadcasterId'),
      account = switch (value['account']) {
        null || 'user' => KickChatAccount.user,
        'bot' => KickChatAccount.bot,
        _ => throw ArgumentError('account must be user or bot.'),
      },
      replyToMessageId = value['replyToMessageId'] == null
          ? null
          : kickMessageId(value['replyToMessageId']);

  final String message;
  final int? broadcasterId;
  final KickChatAccount account;
  final String? replyToMessageId;

  RuntimeMap toRuntime() => {
    'message': message,
    'account': account.name,
    if (broadcasterId != null) 'broadcasterId': broadcasterId,
    if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
  };

  RuntimeMap toRequest({Object? defaultBroadcasterId}) => {
    'content': message,
    'type': account.name,
    if (account == KickChatAccount.user)
      'broadcaster_user_id': kickUserId(
        broadcasterId ?? defaultBroadcasterId,
        'broadcasterId',
      ),
    if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
  };
}

final class KickModerationConfig {
  KickModerationConfig.fromRuntime(RuntimeMap value, {bool timeout = false})
    : userId = kickUserId(value['userId'], 'userId'),
      broadcasterId = value['broadcasterId'] == null
          ? null
          : kickUserId(value['broadcasterId'], 'broadcasterId'),
      reason = _reason(value['reason']),
      durationMinutes = timeout ? _duration(value['durationMinutes']) : null {
    if (!timeout && value['durationMinutes'] != null) {
      throw ArgumentError('durationMinutes is only supported for timeouts.');
    }
  }

  final int userId;
  final int? broadcasterId;
  final String? reason;
  final int? durationMinutes;

  RuntimeMap toRuntime() => {
    'userId': userId,
    if (broadcasterId != null) 'broadcasterId': broadcasterId,
    if (reason != null) 'reason': reason,
    if (durationMinutes != null) 'durationMinutes': durationMinutes,
  };

  RuntimeMap toRequest({Object? defaultBroadcasterId, bool unban = false}) => {
    'broadcaster_user_id': kickUserId(
      broadcasterId ?? defaultBroadcasterId,
      'broadcasterId',
    ),
    'user_id': userId,
    if (!unban && reason != null) 'reason': reason,
    if (!unban && durationMinutes != null) 'duration': durationMinutes,
  };
}

String? _reason(Object? value) {
  if (value == null) return null;
  if (value is! String || value.runes.length > 100) {
    throw ArgumentError('reason must contain at most 100 characters.');
  }
  return value;
}

int _duration(Object? value) {
  if (value is! num ||
      !value.isFinite ||
      value != value.roundToDouble() ||
      value < 1 ||
      value > 10080) {
    throw ArgumentError('durationMinutes must be between 1 and 10080.');
  }
  return value.toInt();
}
