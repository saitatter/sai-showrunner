import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

final class TwitchBroadcasterConfig {
  const TwitchBroadcasterConfig({this.broadcasterId});

  factory TwitchBroadcasterConfig.fromRuntime(RuntimeMap value) =>
      TwitchBroadcasterConfig(broadcasterId: _string(value['broadcasterId']));

  final String? broadcasterId;

  RuntimeMap toRuntime() => {
    if (broadcasterId != null) 'broadcasterId': broadcasterId,
  };
}

final class TwitchClipConfig {
  const TwitchClipConfig({this.broadcasterId, this.createAfterDelay = true});

  factory TwitchClipConfig.fromRuntime(RuntimeMap value) => TwitchClipConfig(
    broadcasterId: _string(value['broadcasterId']),
    createAfterDelay: _bool(value['createAfterDelay'], fallback: true),
  );

  final String? broadcasterId;
  final bool createAfterDelay;

  RuntimeMap toRuntime() => {
    if (broadcasterId != null) 'broadcasterId': broadcasterId,
    'createAfterDelay': createAfterDelay,
  };
}

final class TwitchChatConfig {
  const TwitchChatConfig({this.broadcasterId, this.moderatorId, this.message});

  factory TwitchChatConfig.fromRuntime(RuntimeMap value) => TwitchChatConfig(
    broadcasterId: _string(value['broadcasterId']),
    moderatorId: _string(value['moderatorId']),
    message: _string(value['message']),
  );

  final String? broadcasterId;
  final String? moderatorId;
  final String? message;

  RuntimeMap toRuntime() => {
    if (broadcasterId != null) 'broadcasterId': broadcasterId,
    if (moderatorId != null) 'moderatorId': moderatorId,
    if (message != null) 'message': message,
  };
}

final class TwitchAnnouncementConfig {
  const TwitchAnnouncementConfig({
    this.broadcasterId,
    this.moderatorId,
    this.message,
    this.color,
  });

  factory TwitchAnnouncementConfig.fromRuntime(RuntimeMap value) =>
      TwitchAnnouncementConfig(
        broadcasterId: _string(value['broadcasterId']),
        moderatorId: _string(value['moderatorId']),
        message: _string(value['message']),
        color: _string(value['color']),
      );

  final String? broadcasterId;
  final String? moderatorId;
  final String? message;
  final String? color;

  RuntimeMap toRuntime() => {
    if (broadcasterId != null) 'broadcasterId': broadcasterId,
    if (moderatorId != null) 'moderatorId': moderatorId,
    if (message != null) 'message': message,
    if (color != null) 'color': color,
  };
}

final class TwitchShoutoutConfig {
  const TwitchShoutoutConfig({
    this.broadcasterId,
    this.moderatorId,
    this.streamer,
    this.viewerId,
  });

  factory TwitchShoutoutConfig.fromRuntime(RuntimeMap value) =>
      TwitchShoutoutConfig(
        broadcasterId: _string(value['broadcasterId']),
        moderatorId: _string(value['moderatorId']),
        streamer: _string(value['streamer']),
        viewerId: _string(value['viewerId']),
      );

  final String? broadcasterId;
  final String? moderatorId;
  final String? streamer;
  final String? viewerId;

  RuntimeMap toRuntime() => {
    if (broadcasterId != null) 'broadcasterId': broadcasterId,
    if (moderatorId != null) 'moderatorId': moderatorId,
    if (streamer != null) 'streamer': streamer,
    if (viewerId != null) 'viewerId': viewerId,
  };
}

final class TwitchStreamMarkerConfig {
  const TwitchStreamMarkerConfig({this.broadcasterId, this.markerName});

  factory TwitchStreamMarkerConfig.fromRuntime(RuntimeMap value) =>
      TwitchStreamMarkerConfig(
        broadcasterId: _string(value['broadcasterId']),
        markerName: _string(value['markerName']),
      );

  final String? broadcasterId;
  final String? markerName;

  RuntimeMap toRuntime() => {
    if (broadcasterId != null) 'broadcasterId': broadcasterId,
    if (markerName != null) 'markerName': markerName,
  };
}

final class TwitchAdConfig {
  const TwitchAdConfig({this.broadcasterId, this.duration});

  factory TwitchAdConfig.fromRuntime(RuntimeMap value) => TwitchAdConfig(
    broadcasterId: _string(value['broadcasterId']),
    duration: _number(value['duration']),
  );

  final String? broadcasterId;
  final num? duration;

  RuntimeMap toRuntime() => {
    if (broadcasterId != null) 'broadcasterId': broadcasterId,
    if (duration != null) 'duration': duration,
  };
}

final class TwitchPredictionConfig {
  const TwitchPredictionConfig({
    this.broadcasterId,
    this.title,
    this.duration,
    this.outcomes = const [],
  });

  factory TwitchPredictionConfig.fromRuntime(RuntimeMap value) =>
      TwitchPredictionConfig(
        broadcasterId: _string(value['broadcasterId']),
        title: _string(value['title']),
        duration: _number(value['duration']),
        outcomes: _list(value['outcomes']),
      );

  final String? broadcasterId;
  final String? title;
  final num? duration;
  final List<Object?> outcomes;

  RuntimeMap toRuntime() => {
    if (broadcasterId != null) 'broadcasterId': broadcasterId,
    if (title != null) 'title': title,
    if (duration != null) 'duration': duration,
    'outcomes': outcomes,
  };
}

final class TwitchStreamInfoConfig {
  const TwitchStreamInfoConfig({
    this.broadcasterId,
    this.title,
    this.categoryId,
    this.tags,
  });

  factory TwitchStreamInfoConfig.fromRuntime(RuntimeMap value) =>
      TwitchStreamInfoConfig(
        broadcasterId: _string(value['broadcasterId']),
        title: _string(value['title']),
        categoryId: _string(value['categoryId']),
        tags: value['tags'] is List ? _list(value['tags']) : null,
      );

  final String? broadcasterId;
  final String? title;
  final String? categoryId;
  final List<Object?>? tags;

  RuntimeMap toRuntime() => {
    if (broadcasterId != null) 'broadcasterId': broadcasterId,
    if (title != null) 'title': title,
    if (categoryId != null) 'categoryId': categoryId,
    if (tags != null) 'tags': tags,
  };
}

final class TwitchPollConfig {
  const TwitchPollConfig({
    this.broadcasterId,
    this.title,
    this.duration,
    this.choices = const [],
  });

  factory TwitchPollConfig.fromRuntime(RuntimeMap value) => TwitchPollConfig(
    broadcasterId: _string(value['broadcasterId']),
    title: _string(value['title']),
    duration: _number(value['duration']),
    choices: _list(value['choices']),
  );

  final String? broadcasterId;
  final String? title;
  final num? duration;
  final List<Object?> choices;

  RuntimeMap toRuntime() => {
    if (broadcasterId != null) 'broadcasterId': broadcasterId,
    if (title != null) 'title': title,
    if (duration != null) 'duration': duration,
    'choices': choices,
  };
}

final class TwitchRaidConfig {
  const TwitchRaidConfig({this.broadcasterId, this.target, this.targetId});

  factory TwitchRaidConfig.fromRuntime(RuntimeMap value) => TwitchRaidConfig(
    broadcasterId: _string(value['broadcasterId']),
    target: _string(value['target']),
    targetId: _string(value['targetId']),
  );

  final String? broadcasterId;
  final String? target;
  final String? targetId;

  RuntimeMap toRuntime() => {
    if (broadcasterId != null) 'broadcasterId': broadcasterId,
    if (target != null) 'target': target,
    if (targetId != null) 'targetId': targetId,
  };
}

class TwitchModerationConfig {
  const TwitchModerationConfig({
    this.broadcasterId,
    this.moderatorId,
    this.viewerId,
    this.viewer,
    this.reason,
  });

  factory TwitchModerationConfig.fromRuntime(RuntimeMap value) =>
      TwitchModerationConfig(
        broadcasterId: _string(value['broadcasterId']),
        moderatorId: _string(value['moderatorId']),
        viewerId: _string(value['viewerId']),
        viewer: _string(value['viewer']),
        reason: _string(value['reason']),
      );

  final String? broadcasterId;
  final String? moderatorId;
  final String? viewerId;
  final String? viewer;
  final String? reason;

  RuntimeMap toRuntime() => {
    if (broadcasterId != null) 'broadcasterId': broadcasterId,
    if (moderatorId != null) 'moderatorId': moderatorId,
    if (viewerId != null) 'viewerId': viewerId,
    if (viewer != null) 'viewer': viewer,
    if (reason != null) 'reason': reason,
  };
}

final class TwitchTimeoutConfig extends TwitchModerationConfig {
  const TwitchTimeoutConfig({
    super.broadcasterId,
    super.moderatorId,
    super.viewerId,
    super.viewer,
    super.reason,
    this.duration,
  });

  factory TwitchTimeoutConfig.fromRuntime(RuntimeMap value) =>
      TwitchTimeoutConfig(
        broadcasterId: _string(value['broadcasterId']),
        moderatorId: _string(value['moderatorId']),
        viewerId: _string(value['viewerId']),
        viewer: _string(value['viewer']),
        reason: _string(value['reason']),
        duration: _number(value['duration']),
      );

  final num? duration;

  @override
  RuntimeMap toRuntime() => {
    ...super.toRuntime(),
    if (duration != null) 'duration': duration,
  };
}

typedef TwitchConfigDecoder<C> = C Function(RuntimeMap value);
typedef TwitchConfigEncoder<C> = RuntimeMap Function(C value);

final class TwitchConfigCodec<C> implements PluginConfigCodec<C> {
  const TwitchConfigCodec(this._decoder, this._encoder);

  final TwitchConfigDecoder<C> _decoder;
  final TwitchConfigEncoder<C> _encoder;

  @override
  C decode(RuntimeMap value) => _decoder(value);

  @override
  RuntimeMap encode(C value) => _encoder(value);
}

final twitchBroadcasterConfigCodec = TwitchConfigCodec(
  TwitchBroadcasterConfig.fromRuntime,
  (TwitchBroadcasterConfig value) => value.toRuntime(),
);
final twitchClipConfigCodec = TwitchConfigCodec(
  TwitchClipConfig.fromRuntime,
  (TwitchClipConfig value) => value.toRuntime(),
);
final twitchChatConfigCodec = TwitchConfigCodec(
  TwitchChatConfig.fromRuntime,
  (TwitchChatConfig value) => value.toRuntime(),
);
final twitchAnnouncementConfigCodec = TwitchConfigCodec(
  TwitchAnnouncementConfig.fromRuntime,
  (TwitchAnnouncementConfig value) => value.toRuntime(),
);
final twitchShoutoutConfigCodec = TwitchConfigCodec(
  TwitchShoutoutConfig.fromRuntime,
  (TwitchShoutoutConfig value) => value.toRuntime(),
);
final twitchStreamMarkerConfigCodec = TwitchConfigCodec(
  TwitchStreamMarkerConfig.fromRuntime,
  (TwitchStreamMarkerConfig value) => value.toRuntime(),
);
final twitchAdConfigCodec = TwitchConfigCodec(
  TwitchAdConfig.fromRuntime,
  (TwitchAdConfig value) => value.toRuntime(),
);
final twitchPredictionConfigCodec = TwitchConfigCodec(
  TwitchPredictionConfig.fromRuntime,
  (TwitchPredictionConfig value) => value.toRuntime(),
);
final twitchStreamInfoConfigCodec = TwitchConfigCodec(
  TwitchStreamInfoConfig.fromRuntime,
  (TwitchStreamInfoConfig value) => value.toRuntime(),
);
final twitchPollConfigCodec = TwitchConfigCodec(
  TwitchPollConfig.fromRuntime,
  (TwitchPollConfig value) => value.toRuntime(),
);
final twitchRaidConfigCodec = TwitchConfigCodec(
  TwitchRaidConfig.fromRuntime,
  (TwitchRaidConfig value) => value.toRuntime(),
);
final twitchModerationConfigCodec = TwitchConfigCodec(
  TwitchModerationConfig.fromRuntime,
  (TwitchModerationConfig value) => value.toRuntime(),
);
final twitchTimeoutConfigCodec = TwitchConfigCodec(
  TwitchTimeoutConfig.fromRuntime,
  (TwitchTimeoutConfig value) => value.toRuntime(),
);

String? _string(Object? value) => value?.toString();

num? _number(Object? value) => value is num ? value : null;

bool _bool(Object? value, {required bool fallback}) {
  if (value is bool) return value;
  return switch (value?.toString().toLowerCase()) {
    'true' => true,
    'false' => false,
    _ => fallback,
  };
}

List<Object?> _list(Object? value) => value is List ? [...value] : const [];
