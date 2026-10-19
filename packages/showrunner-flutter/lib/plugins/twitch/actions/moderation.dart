part of '../actions.dart';

List<DartActionContract> _twitchModerationActions(
  TwitchTransport transport,
  ResourceRepository? viewerGroupRepository,
) => [
  ActionSpec<TwitchTimeoutConfig, RuntimeMap>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('timeout'),
    displayName: 'Timeout Viewer',
    configSchema: _timeoutSchema,
    configCodec: twitchTimeoutConfigCodec,
    invoke: (config, context) =>
        _ban(transport, config, context, duration: config.duration),
  ),
  ActionSpec<TwitchModerationConfig, RuntimeMap>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('ban'),
    displayName: 'Ban Viewer',
    configSchema: _moderationSchema,
    configCodec: twitchModerationConfigCodec,
    invoke: (config, context) => _ban(transport, config, context),
  ),
  ActionSpec<TwitchModerationConfig, RuntimeMap>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('unban'),
    displayName: 'Unban Viewer',
    configSchema: _moderationSchema,
    configCodec: twitchModerationConfigCodec,
    invoke: (config, context) =>
        transport.request('DELETE', '/helix/moderation/bans', {
          'broadcaster_id': _idValue(
            config.broadcasterId,
            context,
            'broadcasterId',
          ),
          'moderator_id': _idValue(config.moderatorId, context, 'moderatorId'),
          'user_id': config.viewerId ?? config.viewer,
        }, {}),
  ),
  ActionSpec<TwitchViewerGroupConfig, Object?>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('addViewerToGroup'),
    displayName: 'Add Viewer to Group',
    configSchema: _viewerGroupSchema,
    configCodec: twitchViewerGroupConfigCodec,
    invoke: (config, context) =>
        _updateViewerGroup(viewerGroupRepository, config, add: true),
  ),
  ActionSpec<TwitchViewerGroupConfig, Object?>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('removeViewerFromGroup'),
    displayName: 'Remove Viewer from Group',
    configSchema: _viewerGroupSchema,
    configCodec: twitchViewerGroupConfigCodec,
    invoke: (config, context) =>
        _updateViewerGroup(viewerGroupRepository, config, add: false),
  ),
  ActionSpec<TwitchClearViewerGroupConfig, Object?>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('clearViewerGroup'),
    displayName: 'Clear Viewer Group',
    configSchema: _clearViewerGroupSchema,
    configCodec: twitchClearViewerGroupConfigCodec,
    invoke: (config, context) =>
        _clearViewerGroup(viewerGroupRepository, config),
  ),
];
