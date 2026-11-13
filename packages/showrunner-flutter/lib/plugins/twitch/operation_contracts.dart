import '../../runtime/expression.dart';
import 'contracts.dart';

// Helix operation inputs are decoded before any network call. Error messages
// name the field, never its value (which may contain private moderation text).
String? _text(RuntimeMap value, String key, {bool required = false}) {
  final raw = value[key];
  if (raw == null || raw == '') {
    if (required) throw ArgumentError('$key is required.');
    return null;
  }
  if (raw is! String || raw.trim().isEmpty) {
    throw ArgumentError('$key must be non-empty text.');
  }
  return raw;
}

int? _integer(RuntimeMap value, String key, int min, int max) {
  final raw = value[key];
  if (raw == null) return null;
  if (raw is! num ||
      !raw.isFinite ||
      raw != raw.roundToDouble() ||
      raw < min ||
      raw > max) {
    throw ArgumentError('$key must be an integer between $min and $max.');
  }
  return raw.toInt();
}

List<String> _ids(
  RuntimeMap value,
  String key,
  int max, {
  bool required = false,
}) {
  final raw = value[key];
  if (raw == null && !required) return const [];
  if (raw is! List ||
      raw.length > max ||
      (required && raw.isEmpty) ||
      raw.any((id) => id is! String || id.trim().isEmpty)) {
    throw ArgumentError('$key must contain ${required ? 1 : 0} to $max IDs.');
  }
  return List<String>.unmodifiable(raw.cast<String>());
}

final class TwitchPageConfig {
  TwitchPageConfig.fromRuntime(RuntimeMap value)
    : broadcasterId = _text(value, 'broadcasterId'),
      ids = _ids(value, 'ids', 20),
      first = _integer(value, 'first', 1, 20),
      after = _text(value, 'after');
  final String? broadcasterId;
  final List<String> ids;
  final int? first;
  final String? after;
  RuntimeMap toRuntime() => {
    if (broadcasterId != null) 'broadcasterId': broadcasterId,
    'ids': ids,
    if (first != null) 'first': first,
    if (after != null) 'after': after,
  };
}

final class TwitchLifecycleConfig {
  TwitchLifecycleConfig.fromRuntime(RuntimeMap value)
    : broadcasterId = _text(value, 'broadcasterId'),
      id = _text(value, 'id', required: true)!,
      winningOutcomeId = _text(value, 'winningOutcomeId');
  final String? broadcasterId;
  final String id;
  final String? winningOutcomeId;
  RuntimeMap toRuntime() => {
    if (broadcasterId != null) 'broadcasterId': broadcasterId,
    'id': id,
    if (winningOutcomeId != null) 'winningOutcomeId': winningOutcomeId,
  };
}

final class TwitchPinConfig {
  TwitchPinConfig.fromRuntime(RuntimeMap value)
    : broadcasterId = _text(value, 'broadcasterId'),
      moderatorId = _text(value, 'moderatorId'),
      messageId = _text(value, 'messageId', required: true)!,
      duration = _integer(value, 'duration', 30, 1800);
  final String? broadcasterId;
  final String? moderatorId;
  final String messageId;
  final int? duration;
  RuntimeMap toRuntime() => {
    if (broadcasterId != null) 'broadcasterId': broadcasterId,
    if (moderatorId != null) 'moderatorId': moderatorId,
    'messageId': messageId,
    if (duration != null) 'duration': duration,
  };
}

final class TwitchRoleConfig {
  TwitchRoleConfig.fromRuntime(RuntimeMap value)
    : broadcasterId = _text(value, 'broadcasterId'),
      viewerId = _text(value, 'viewerId', required: true)!;
  final String? broadcasterId;
  final String viewerId;
  RuntimeMap toRuntime() => {
    if (broadcasterId != null) 'broadcasterId': broadcasterId,
    'viewerId': viewerId,
  };
}

final class TwitchWarningConfig {
  TwitchWarningConfig.fromRuntime(RuntimeMap value)
    : broadcasterId = _text(value, 'broadcasterId'),
      moderatorId = _text(value, 'moderatorId'),
      viewerId = _text(value, 'viewerId', required: true)!,
      reason = _text(value, 'reason', required: true)! {
    if (reason.runes.length > 500)
      throw ArgumentError('reason exceeds 500 characters.');
  }
  final String? broadcasterId;
  final String? moderatorId;
  final String viewerId;
  final String reason;
  RuntimeMap toRuntime() => {
    if (broadcasterId != null) 'broadcasterId': broadcasterId,
    if (moderatorId != null) 'moderatorId': moderatorId,
    'viewerId': viewerId,
    'reason': reason,
  };
}

final class TwitchAutoModDecisionConfig {
  TwitchAutoModDecisionConfig.fromRuntime(RuntimeMap value)
    : moderatorId = _text(value, 'moderatorId'),
      messageId = _text(value, 'messageId', required: true)!;
  final String? moderatorId;
  final String messageId;
  RuntimeMap toRuntime() => {
    if (moderatorId != null) 'moderatorId': moderatorId,
    'messageId': messageId,
  };
}

final twitchPageConfigCodec = TwitchConfigCodec(
  TwitchPageConfig.fromRuntime,
  (value) => value.toRuntime(),
);
final twitchLifecycleConfigCodec = TwitchConfigCodec(
  TwitchLifecycleConfig.fromRuntime,
  (value) => value.toRuntime(),
);
final twitchPinConfigCodec = TwitchConfigCodec(
  TwitchPinConfig.fromRuntime,
  (value) => value.toRuntime(),
);
final twitchRoleConfigCodec = TwitchConfigCodec(
  TwitchRoleConfig.fromRuntime,
  (value) => value.toRuntime(),
);
final twitchWarningConfigCodec = TwitchConfigCodec(
  TwitchWarningConfig.fromRuntime,
  (value) => value.toRuntime(),
);
final twitchAutoModDecisionConfigCodec = TwitchConfigCodec(
  TwitchAutoModDecisionConfig.fromRuntime,
  (value) => value.toRuntime(),
);

/// Moderation payloads stay on their dedicated triggers; they are never chat
/// messages. The details include provider-specific settings / term changes.
final class TwitchModerationEvent {
  TwitchModerationEvent.fromRuntime(RuntimeMap value)
    : viewerId = value['viewerId'] as String?,
      moderatorId = value['moderatorId'] as String?,
      messageId = value['messageId'] as String?,
      message = value['message'] as String?,
      reason = value['reason'] as String?,
      status = value['status'] as String?,
      details = Map<String, dynamic>.unmodifiable(value);
  final String? viewerId;
  final String? moderatorId;
  final String? messageId;
  final String? message;
  final String? reason;
  final String? status;
  final RuntimeMap details;
  RuntimeMap toRuntime() => {
    if (viewerId != null) 'viewerId': viewerId,
    if (moderatorId != null) 'moderatorId': moderatorId,
    if (messageId != null) 'messageId': messageId,
    if (message != null) 'message': message,
    if (reason != null) 'reason': reason,
    if (status != null) 'status': status,
    'details': details,
  };
}
