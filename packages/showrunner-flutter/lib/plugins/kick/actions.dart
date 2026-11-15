import '../../runtime/expression.dart';
import '../../schema/data_input.dart';
import '../../services/plugin_event_hub.dart';
import '../registry/plugin_contract.dart';
import 'contracts.dart';

typedef KickRequest =
    Future<RuntimeMap> Function(
      String method,
      String path,
      RuntimeMap query,
      Object? body,
    );

final class KickTransport {
  const KickTransport(this.request, {this.readBroadcasterId});
  final KickRequest request;
  final Future<Object?> Function()? readBroadcasterId;
}

final class KickEmptyConfig {
  const KickEmptyConfig();
}

final class KickDeleteConfig {
  KickDeleteConfig.fromRuntime(RuntimeMap value)
    : messageId = kickMessageId(value['messageId']);
  final String messageId;
  RuntimeMap toRuntime() => {'messageId': messageId};
}

final class _Codec<T> implements PluginConfigCodec<T> {
  const _Codec(this.read, this.write);
  final T Function(RuntimeMap) read;
  final RuntimeMap Function(T) write;
  @override
  T decode(RuntimeMap value) => read(value);
  @override
  RuntimeMap encode(T value) => write(value);
}

DartDataInputSchema _object(String label, List<DartDataInputSchema> fields) =>
    DartDataInputSchema(
      label: label,
      kind: DartDataInputKind.object,
      fields: fields,
    );

const _broadcaster = DartDataInputSchema(
  label: 'Broadcaster ID',
  key: 'broadcasterId',
  kind: DartDataInputKind.text,
);
const _user = DartDataInputSchema(
  label: 'User ID',
  key: 'userId',
  kind: DartDataInputKind.text,
  required: true,
);
const _reason = DartDataInputSchema(
  label: 'Reason (up to 100 characters)',
  key: 'reason',
  kind: DartDataInputKind.text,
);

DartPluginManifest createKickPlugin(
  KickTransport transport, {
  DartPluginEventHub? eventHub,
}) => DartPluginManifest(
  id: PluginId('kick'),
  name: 'Kick',
  settings: const [
    SettingSpec<String>(id: SettingId('clientId'), displayName: 'Client ID'),
    SettingSpec<String>(
      id: SettingId('clientSecret'),
      displayName: 'Client Secret',
      secret: true,
    ),
    SettingSpec<String>(
      id: SettingId('accessToken'),
      displayName: 'Access Token',
      secret: true,
    ),
    SettingSpec<String>(
      id: SettingId('refreshToken'),
      displayName: 'Refresh Token',
      secret: true,
    ),
    SettingSpec<String>(
      id: SettingId('broadcasterId'),
      displayName: 'Broadcaster ID',
    ),
    SettingSpec<String>(
      id: SettingId('publicWebhookUrl'),
      displayName: 'Public HTTPS Webhook URL',
    ),
    SettingSpec<int>(
      id: SettingId('webhookPort'),
      displayName: 'Local Webhook Port',
      defaultValue: 53544,
    ),
  ],
  states: const [
    StateSpec(
      id: StateId('connection'),
      displayName: 'Connection',
      initialValue: 'unconfigured',
    ),
  ],
  actions: [
    ActionSpec<KickSendChatConfig, RuntimeMap>(
      pluginId: PluginId('kick'),
      actionId: ActionId('sendChatMessage'),
      displayName: 'Send Chat Message',
      configCodec: _Codec(
        KickSendChatConfig.fromRuntime,
        (value) => value.toRuntime(),
      ),
      configSchema: _object('Kick chat message', [
        _broadcaster,
        const DartDataInputSchema(
          label: 'Message',
          key: 'message',
          kind: DartDataInputKind.multilineText,
          required: true,
        ),
        const DartDataInputSchema(
          label: 'Account (user or app bot)',
          key: 'account',
          kind: DartDataInputKind.enumeration,
          options: ['user', 'bot'],
          defaultValue: 'user',
        ),
        const DartDataInputSchema(
          label: 'Reply to message ID',
          key: 'replyToMessageId',
          kind: DartDataInputKind.text,
        ),
      ]),
      resultSchema: _object('Sent message', [
        const DartDataInputSchema(
          label: 'Message ID',
          key: 'messageId',
          kind: DartDataInputKind.text,
          required: true,
        ),
      ]),
      invoke: (config, context) async {
        final response = await transport.request(
          'POST',
          '/public/v1/chat',
          const {},
          config.toRequest(
            defaultBroadcasterId:
                context.contextState['broadcasterId'] ??
                await transport.readBroadcasterId?.call(),
          ),
        );
        final data = response['data'];
        if (data is! Map || data['is_sent'] != true) {
          throw StateError('Kick did not confirm message delivery.');
        }
        return {'messageId': kickMessageId(data['message_id'])};
      },
    ),
    ActionSpec<KickDeleteConfig, RuntimeMap>(
      pluginId: PluginId('kick'),
      actionId: ActionId('deleteMessage'),
      displayName: 'Delete Chat Message',
      configCodec: _Codec(
        KickDeleteConfig.fromRuntime,
        (value) => value.toRuntime(),
      ),
      configSchema: _object('Delete message', [
        const DartDataInputSchema(
          label: 'Message ID',
          key: 'messageId',
          kind: DartDataInputKind.text,
          required: true,
        ),
      ]),
      invoke: (config, _) => transport.request(
        'DELETE',
        '/public/v1/chat/${config.messageId}',
        const {},
        null,
      ),
    ),
    for (final action in ['banUser', 'timeoutUser', 'unbanUser'])
      ActionSpec<KickModerationConfig, RuntimeMap>(
        pluginId: PluginId('kick'),
        actionId: ActionId(action),
        displayName: switch (action) {
          'banUser' => 'Ban User',
          'timeoutUser' => 'Timeout User',
          _ => 'Unban User',
        },
        configCodec: _Codec(
          (value) => KickModerationConfig.fromRuntime(
            value,
            timeout: action == 'timeoutUser',
          ),
          (value) => value.toRuntime(),
        ),
        configSchema: _object('Kick moderation', [
          _broadcaster,
          _user,
          if (action != 'unbanUser') _reason,
          if (action == 'timeoutUser')
            const DartDataInputSchema(
              label: 'Duration (minutes, 1–10080)',
              key: 'durationMinutes',
              kind: DartDataInputKind.number,
              required: true,
              defaultValue: 1,
            ),
        ]),
        invoke: (config, context) async => await transport.request(
          action == 'unbanUser' ? 'DELETE' : 'POST',
          '/public/v1/moderation/bans',
          const {},
          config.toRequest(
            defaultBroadcasterId:
                context.contextState['broadcasterId'] ??
                await transport.readBroadcasterId?.call(),
            unban: action == 'unbanUser',
          ),
        ),
      ),
  ],
  triggers: [
    for (final entry in const {
      'chatMessage': ('kickChatMessage', 'Chat Message'),
      'userBanned': ('kickUserBanned', 'User Banned'),
      'userTimedOut': ('kickUserTimedOut', 'User Timed Out'),
    }.entries)
      TriggerSpec<KickEmptyConfig, RuntimeMap>(
        pluginId: PluginId('kick'),
        triggerId: TriggerId(entry.key),
        displayName: entry.value.$2,
        configCodec: _Codec((_) => const KickEmptyConfig(), (_) => const {}),
        listen: () => eventHub?.stream(entry.value.$1) ?? const Stream.empty(),
        eventEncoder: (event) => event,
        eventSchema: _object('Kick event', [
          const DartDataInputSchema(
            label: 'Viewer ID',
            key: 'viewerId',
            kind: DartDataInputKind.text,
            required: true,
          ),
          const DartDataInputSchema(
            label: 'Viewer name',
            key: 'viewerName',
            kind: DartDataInputKind.text,
            required: true,
          ),
          const DartDataInputSchema(
            label: 'Broadcaster ID',
            key: 'broadcasterId',
            kind: DartDataInputKind.text,
            required: true,
          ),
          if (entry.key == 'chatMessage') ...const [
            DartDataInputSchema(
              label: 'Message',
              key: 'message',
              kind: DartDataInputKind.text,
              required: true,
            ),
            DartDataInputSchema(
              label: 'Message ID',
              key: 'messageId',
              kind: DartDataInputKind.text,
              required: true,
            ),
            DartDataInputSchema(
              label: 'Moderator',
              key: 'isModerator',
              kind: DartDataInputKind.boolean,
              required: true,
            ),
            DartDataInputSchema(
              label: 'Subscriber',
              key: 'isSubscriber',
              kind: DartDataInputKind.boolean,
              required: true,
            ),
            DartDataInputSchema(
              label: 'VIP',
              key: 'isVip',
              kind: DartDataInputKind.boolean,
              required: true,
            ),
            DartDataInputSchema(
              label: 'Owner',
              key: 'isOwner',
              kind: DartDataInputKind.boolean,
              required: true,
            ),
            DartDataInputSchema(
              label: 'Bot',
              key: 'isBot',
              kind: DartDataInputKind.boolean,
              required: true,
            ),
            DartDataInputSchema(
              label: 'Avatar URL',
              key: 'avatarUrl',
              kind: DartDataInputKind.text,
            ),
          ],
          const DartDataInputSchema(
            label: 'Created at',
            key: 'createdAt',
            kind: DartDataInputKind.text,
            required: true,
          ),
          if (entry.key == 'userTimedOut')
            const DartDataInputSchema(
              label: 'Expires at',
              key: 'expiresAt',
              kind: DartDataInputKind.text,
              required: true,
            ),
        ]),
      ),
  ],
);
