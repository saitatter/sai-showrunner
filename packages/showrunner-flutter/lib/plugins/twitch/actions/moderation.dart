part of '../actions.dart';

List<ActionSpec<Map<String, dynamic>, Object?>> _twitchModerationActions(
  TwitchTransport transport,
  ResourceRepository? viewerGroupRepository,
) => [
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('timeout'),
    displayName: 'Timeout Viewer',
    configSchema: _timeoutSchema,
    invoke: (config, context) =>
        _ban(transport, config, context, includeDuration: true),
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('ban'),
    displayName: 'Ban Viewer',
    configSchema: _moderationSchema,
    invoke: (config, context) => _ban(transport, config, context),
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('unban'),
    displayName: 'Unban Viewer',
    configSchema: _moderationSchema,
    invoke: (config, context) =>
        transport.request('DELETE', '/helix/moderation/bans', {
          'broadcaster_id': _id(config, context, 'broadcasterId'),
          'moderator_id': _id(config, context, 'moderatorId'),
          'user_id': config['viewerId'],
        }, {}),
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('addViewerToGroup'),
    displayName: 'Add Viewer to Group',
    configSchema: _viewerGroupSchema,
    invoke: (config, context) =>
        _updateViewerGroup(viewerGroupRepository, config, add: true),
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('removeViewerFromGroup'),
    displayName: 'Remove Viewer from Group',
    configSchema: _viewerGroupSchema,
    invoke: (config, context) =>
        _updateViewerGroup(viewerGroupRepository, config, add: false),
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('clearViewerGroup'),
    displayName: 'Clear Viewer Group',
    configSchema: _clearViewerGroupSchema,
    invoke: (config, context) =>
        _clearViewerGroup(viewerGroupRepository, config),
  ),
];
