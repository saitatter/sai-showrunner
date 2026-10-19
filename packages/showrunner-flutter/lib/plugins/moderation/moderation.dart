/// Moderation plugin boundary for the Flutter desktop runtime.
///
/// Moderation actions currently live in the YouTube and Twitch manifests;
/// this directory is the target home for shared moderation contracts.
library;

import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';
import '../../schema/data_input.dart';
import 'runtime.dart';

final class ModerationChatConfig {
  const ModerationChatConfig({
    this.platform,
    this.messageId,
    this.viewerId,
    this.viewerName,
    this.message,
    this.badges,
    this.isModerator,
    this.isMember,
    this.isOwner,
  });

  factory ModerationChatConfig.fromRuntime(RuntimeMap value) =>
      ModerationChatConfig(
        platform: _string(value['platform']),
        messageId: _string(value['messageId']),
        viewerId: _string(value['viewerId']),
        viewerName: _string(value['viewerName']),
        message: _string(value['message']),
        badges: _string(value['badges']),
        isModerator: _bool(value['isModerator']),
        isMember: _bool(value['isMember']),
        isOwner: _bool(value['isOwner']),
      );

  final String? platform;
  final String? messageId;
  final String? viewerId;
  final String? viewerName;
  final String? message;
  final String? badges;
  final bool? isModerator;
  final bool? isMember;
  final bool? isOwner;

  RuntimeMap toRuntime() => {
    if (platform != null) 'platform': platform,
    if (messageId != null) 'messageId': messageId,
    if (viewerId != null) 'viewerId': viewerId,
    if (viewerName != null) 'viewerName': viewerName,
    if (message != null) 'message': message,
    if (badges != null) 'badges': badges,
    if (isModerator != null) 'isModerator': isModerator,
    if (isMember != null) 'isMember': isMember,
    if (isOwner != null) 'isOwner': isOwner,
  };
}

final class ModerationOverrideConfig {
  const ModerationOverrideConfig({this.messageId, this.action = 'approve'});

  factory ModerationOverrideConfig.fromRuntime(RuntimeMap value) =>
      ModerationOverrideConfig(
        messageId: _string(value['messageId']),
        action: _string(value['action']) ?? 'approve',
      );

  final String? messageId;
  final String action;
}

final class ModerationEmptyConfig {
  const ModerationEmptyConfig();
}

final class ModerationConfigCodec<C> implements PluginConfigCodec<C> {
  const ModerationConfigCodec(this._decoder, this._encoder);

  final C Function(RuntimeMap) _decoder;
  final RuntimeMap Function(C value) _encoder;

  @override
  C decode(RuntimeMap value) => _decoder(value);

  @override
  RuntimeMap encode(C value) => _encoder(value);
}

final moderationChatConfigCodec = ModerationConfigCodec(
  ModerationChatConfig.fromRuntime,
  (ModerationChatConfig value) => value.toRuntime(),
);
final moderationOverrideConfigCodec = ModerationConfigCodec(
  ModerationOverrideConfig.fromRuntime,
  (ModerationOverrideConfig value) => {
    if (value.messageId != null) 'messageId': value.messageId,
    'action': value.action,
  },
);
final moderationEmptyConfigCodec = ModerationConfigCodec(
  (value) => const ModerationEmptyConfig(),
  (ModerationEmptyConfig value) => const <String, dynamic>{},
);

String? _string(Object? value) => value?.toString();

bool? _bool(Object? value) => value is bool ? value : null;

const _moderateChatSchema = DartDataInputSchema(
  label: 'Moderation chat message',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Platform',
      key: 'platform',
      kind: DartDataInputKind.text,
      defaultValue: 'twitch',
    ),
    DartDataInputSchema(
      label: 'Message ID',
      key: 'messageId',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      label: 'Viewer ID',
      key: 'viewerId',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      label: 'Viewer name',
      key: 'viewerName',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      label: 'Message',
      key: 'message',
      kind: DartDataInputKind.multilineText,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Badges (comma-separated)',
      key: 'badges',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      label: 'Moderator',
      key: 'isModerator',
      kind: DartDataInputKind.boolean,
    ),
    DartDataInputSchema(
      label: 'Member',
      key: 'isMember',
      kind: DartDataInputKind.boolean,
    ),
    DartDataInputSchema(
      label: 'Owner',
      key: 'isOwner',
      kind: DartDataInputKind.boolean,
    ),
  ],
);

const _overrideSchema = DartDataInputSchema(
  label: 'Moderation override',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Message ID',
      key: 'messageId',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Action',
      key: 'action',
      kind: DartDataInputKind.enumeration,
      options: ['approve', 'block', 'falsePositive'],
      required: true,
      defaultValue: 'approve',
    ),
  ],
);

const _emptySchema = DartDataInputSchema(
  label: 'Moderation action',
  kind: DartDataInputKind.object,
);

DartPluginManifest createModerationPlugin(ModerationService service) =>
    DartPluginManifest(
      id: PluginId('moderation'),
      name: 'Moderation Docker',
      settings: const [
        SettingSpec(
          id: SettingId('enabled'),
          displayName: 'Enabled',
          type: DartSettingType.boolean,
        ),
        SettingSpec(id: SettingId('apiBaseUrl'), displayName: 'API URL'),
        SettingSpec(
          id: SettingId('apiToken'),
          displayName: 'API Token',
          secret: true,
        ),
        SettingSpec(
          id: SettingId('dashboardWsUrl'),
          displayName: 'Dashboard WebSocket URL',
        ),
        SettingSpec(
          id: SettingId('forwardYouTube'),
          displayName: 'Forward YouTube Chat',
          defaultValue: true,
        ),
      ],
      states: const [
        StateSpec(
          id: StateId('health'),
          displayName: 'Health',
          initialValue: 'unknown',
        ),
      ],
      actions: [
        ActionSpec<ModerationChatConfig, RuntimeMap>(
          pluginId: PluginId('moderation'),
          actionId: ActionId('moderateChatMessage'),
          displayName: 'Filter Chat Message',
          configSchema: _moderateChatSchema,
          configCodec: moderationChatConfigCodec,
          invoke: (config, context) =>
              service.moderateChatMessage(config.toRuntime()),
        ),
        ActionSpec<ModerationEmptyConfig, Object?>(
          pluginId: PluginId('moderation'),
          actionId: ActionId('sendTestMessage'),
          displayName: 'Send Test Moderation Event',
          configSchema: _emptySchema,
          configCodec: moderationEmptyConfigCodec,
          invoke: (config, context) async => service.sendTestMessage(),
        ),
        ActionSpec<ModerationOverrideConfig, RuntimeMap>(
          pluginId: PluginId('moderation'),
          actionId: ActionId('requestOverride'),
          displayName: 'Request Moderation Override',
          configSchema: _overrideSchema,
          configCodec: moderationOverrideConfigCodec,
          invoke: (config, context) => service.requestOverride(
            messageId: config.messageId ?? '',
            action: config.action,
          ),
        ),
      ],
    );
