import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

final class YouTubeEmptyConfig {
  const YouTubeEmptyConfig();
}

final class YouTubeSendChatMessageConfig {
  const YouTubeSendChatMessageConfig({this.liveChatId, this.message});

  factory YouTubeSendChatMessageConfig.fromRuntime(RuntimeMap value) =>
      YouTubeSendChatMessageConfig(
        liveChatId: _asString(value['liveChatId']),
        message: _asString(value['message']),
      );

  final String? liveChatId;
  final String? message;

  RuntimeMap toRuntime() => {
    if (liveChatId != null) 'liveChatId': liveChatId,
    if (message != null) 'message': message,
  };
}

final class YouTubeDeleteMessageConfig {
  const YouTubeDeleteMessageConfig({this.messageId});

  factory YouTubeDeleteMessageConfig.fromRuntime(RuntimeMap value) =>
      YouTubeDeleteMessageConfig(messageId: _asString(value['messageId']));

  final String? messageId;

  RuntimeMap toRuntime() => {if (messageId != null) 'messageId': messageId};
}

final class YouTubeBanUserConfig {
  const YouTubeBanUserConfig({
    this.liveChatId,
    this.channelId,
    this.durationSeconds = 0,
  });

  factory YouTubeBanUserConfig.fromRuntime(RuntimeMap value) =>
      YouTubeBanUserConfig(
        liveChatId: _asString(value['liveChatId']),
        channelId: _asString(value['channelId']),
        durationSeconds: _asInt(value['banDurationSeconds']) ?? 0,
      );

  final String? liveChatId;
  final String? channelId;
  final int durationSeconds;

  RuntimeMap toRuntime() => {
    if (liveChatId != null) 'liveChatId': liveChatId,
    if (channelId != null) 'channelId': channelId,
    'banDurationSeconds': durationSeconds,
  };
}

final class YouTubeRemoveBanConfig {
  const YouTubeRemoveBanConfig({this.banId});

  factory YouTubeRemoveBanConfig.fromRuntime(RuntimeMap value) =>
      YouTubeRemoveBanConfig(banId: _asString(value['banId']));

  final String? banId;

  RuntimeMap toRuntime() => {if (banId != null) 'banId': banId};
}

class YouTubeChatEvent {
  const YouTubeChatEvent({
    required this.viewerId,
    required this.viewerName,
    required this.message,
    required this.messageId,
    required this.avatarUrl,
    required this.isModerator,
    required this.isMember,
    required this.isOwner,
  });

  final String viewerId;
  final String viewerName;
  final String message;
  final String messageId;
  final String avatarUrl;
  final bool isModerator;
  final bool isMember;
  final bool isOwner;
}

final class YouTubeChatMessageEvent extends YouTubeChatEvent {
  const YouTubeChatMessageEvent({
    required super.viewerId,
    required super.viewerName,
    required super.message,
    required super.messageId,
    required super.avatarUrl,
    required super.isModerator,
    required super.isMember,
    required super.isOwner,
  });

  factory YouTubeChatMessageEvent.fromRuntime(RuntimeMap value) =>
      YouTubeChatMessageEvent(
        viewerId: _asString(value['viewerId']) ?? '',
        viewerName: _asString(value['viewerName']) ?? '',
        message: _asString(value['message']) ?? '',
        messageId: _asString(value['messageId']) ?? '',
        avatarUrl: _asString(value['avatarUrl']) ?? '',
        isModerator: value['isModerator'] == true,
        isMember: value['isMember'] == true,
        isOwner: value['isOwner'] == true,
      );
}

final class YouTubePaidEvent extends YouTubeChatEvent {
  const YouTubePaidEvent({
    required super.viewerId,
    required super.viewerName,
    required super.message,
    required super.messageId,
    required super.avatarUrl,
    required super.isModerator,
    required super.isMember,
    required super.isOwner,
    this.amountMicros,
    this.currency,
  });

  factory YouTubePaidEvent.fromRuntime(RuntimeMap value) => YouTubePaidEvent(
    viewerId: _asString(value['viewerId']) ?? '',
    viewerName: _asString(value['viewerName']) ?? '',
    message: _asString(value['message']) ?? '',
    messageId: _asString(value['messageId']) ?? '',
    avatarUrl: _asString(value['avatarUrl']) ?? '',
    isModerator: value['isModerator'] == true,
    isMember: value['isMember'] == true,
    isOwner: value['isOwner'] == true,
    amountMicros: value['amountMicros'] is num
        ? value['amountMicros'] as num
        : null,
    currency: _asString(value['currency']),
  );

  final num? amountMicros;
  final String? currency;
}

final class YouTubeMembershipEvent extends YouTubeChatEvent {
  const YouTubeMembershipEvent({
    required super.viewerId,
    required super.viewerName,
    required super.message,
    required super.messageId,
    required super.avatarUrl,
    required super.isModerator,
    required super.isMember,
    required super.isOwner,
    this.eventType,
    this.memberLevelName,
    this.memberMonth,
  });

  factory YouTubeMembershipEvent.fromRuntime(RuntimeMap value) =>
      YouTubeMembershipEvent(
        viewerId: _asString(value['viewerId']) ?? '',
        viewerName: _asString(value['viewerName']) ?? '',
        message: _asString(value['message']) ?? '',
        messageId: _asString(value['messageId']) ?? '',
        avatarUrl: _asString(value['avatarUrl']) ?? '',
        isModerator: value['isModerator'] == true,
        isMember: value['isMember'] == true,
        isOwner: value['isOwner'] == true,
        eventType: _asString(value['eventType']),
        memberLevelName: _asString(value['memberLevelName']),
        memberMonth: value['memberMonth'] is num
            ? (value['memberMonth'] as num).toInt()
            : null,
      );

  final String? eventType;
  final String? memberLevelName;
  final int? memberMonth;
}

final class YouTubeSendChatMessageConfigCodec
    implements PluginConfigCodec<YouTubeSendChatMessageConfig> {
  const YouTubeSendChatMessageConfigCodec();

  @override
  YouTubeSendChatMessageConfig decode(RuntimeMap value) =>
      YouTubeSendChatMessageConfig.fromRuntime(value);

  @override
  RuntimeMap encode(YouTubeSendChatMessageConfig value) => value.toRuntime();
}

final class YouTubeDeleteMessageConfigCodec
    implements PluginConfigCodec<YouTubeDeleteMessageConfig> {
  const YouTubeDeleteMessageConfigCodec();

  @override
  YouTubeDeleteMessageConfig decode(RuntimeMap value) =>
      YouTubeDeleteMessageConfig.fromRuntime(value);

  @override
  RuntimeMap encode(YouTubeDeleteMessageConfig value) => value.toRuntime();
}

final class YouTubeBanUserConfigCodec
    implements PluginConfigCodec<YouTubeBanUserConfig> {
  const YouTubeBanUserConfigCodec();

  @override
  YouTubeBanUserConfig decode(RuntimeMap value) =>
      YouTubeBanUserConfig.fromRuntime(value);

  @override
  RuntimeMap encode(YouTubeBanUserConfig value) => value.toRuntime();
}

final class YouTubeRemoveBanConfigCodec
    implements PluginConfigCodec<YouTubeRemoveBanConfig> {
  const YouTubeRemoveBanConfigCodec();

  @override
  YouTubeRemoveBanConfig decode(RuntimeMap value) =>
      YouTubeRemoveBanConfig.fromRuntime(value);

  @override
  RuntimeMap encode(YouTubeRemoveBanConfig value) => value.toRuntime();
}

const youtubeSendChatMessageConfigCodec = YouTubeSendChatMessageConfigCodec();
const youtubeDeleteMessageConfigCodec = YouTubeDeleteMessageConfigCodec();
const youtubeBanUserConfigCodec = YouTubeBanUserConfigCodec();
const youtubeRemoveBanConfigCodec = YouTubeRemoveBanConfigCodec();

String? _asString(Object? value) => value?.toString();

int? _asInt(Object? value) => value is num ? value.toInt() : null;
