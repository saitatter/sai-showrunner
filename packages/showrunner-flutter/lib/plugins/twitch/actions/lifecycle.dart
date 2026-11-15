part of '../actions.dart';

final _helixDataResult = _twitchObject('Helix result', [
  DartDataInputSchema(
    label: 'Data',
    key: 'data',
    kind: DartDataInputKind.array,
    itemKind: DartDataInputKind.object,
  ),
  DartDataInputSchema(
    label: 'Pagination',
    key: 'pagination',
    kind: DartDataInputKind.object,
    fields: [_twitchText('Cursor', 'cursor')],
  ),
]);

DartDataInputSchema _pageSchema(String label) => _twitchObject(label, [
  _broadcaster,
  DartDataInputSchema(
    label: 'IDs (optional, up to 20)',
    key: 'ids',
    kind: DartDataInputKind.array,
    itemKind: DartDataInputKind.text,
  ),
  DartDataInputSchema(
    label: 'Page size (1–20)',
    key: 'first',
    kind: DartDataInputKind.number,
  ),
  _twitchText('Next page cursor', 'after'),
]);

DartDataInputSchema _lifecycleSchema(String label, {bool resolve = false}) =>
    _twitchObject(label, [
      _broadcaster,
      _twitchText('Poll / prediction ID', 'id', required: true),
      if (resolve)
        _twitchText('Winning outcome ID', 'winningOutcomeId', required: true),
    ]);

// These actions deliberately expose each lifecycle transition as its own node.
// No hidden get-latest / retry of a mutation: the graph chooses a concrete ID.
List<DartActionContract> _twitchLifecycleActions(TwitchTransport transport) => [
  for (final resource in ['Polls', 'Predictions'])
    ActionSpec<TwitchPageConfig, RuntimeMap>(
      pluginId: PluginId('twitch'),
      actionId: ActionId('get$resource'),
      displayName: 'Get $resource',
      configSchema: _pageSchema('Get $resource'),
      resultSchema: _helixDataResult,
      configCodec: twitchPageConfigCodec,
      invoke: (config, context) =>
          transport.request('GET', '/helix/${resource.toLowerCase()}', {
            'broadcaster_id': _idValue(
              config.broadcasterId,
              context,
              'broadcasterId',
            ),
            if (config.ids.isNotEmpty) 'id': config.ids,
            if (config.first != null) 'first': config.first,
            if (config.after != null) 'after': config.after,
          }, {}),
    ),
  for (final operation in const [
    (
      id: 'terminatePoll',
      label: 'Terminate Poll',
      path: 'polls',
      status: 'TERMINATED',
    ),
    (
      id: 'archivePoll',
      label: 'Archive Poll',
      path: 'polls',
      status: 'ARCHIVED',
    ),
    (
      id: 'lockPrediction',
      label: 'Lock Prediction',
      path: 'predictions',
      status: 'LOCKED',
    ),
    (
      id: 'resolvePrediction',
      label: 'Resolve Prediction',
      path: 'predictions',
      status: 'RESOLVED',
    ),
    (
      id: 'cancelPrediction',
      label: 'Cancel Prediction',
      path: 'predictions',
      status: 'CANCELED',
    ),
  ])
    ActionSpec<TwitchLifecycleConfig, RuntimeMap>(
      pluginId: PluginId('twitch'),
      actionId: ActionId(operation.id),
      displayName: operation.label,
      configSchema: _lifecycleSchema(
        operation.label,
        resolve: operation.status == 'RESOLVED',
      ),
      resultSchema: _helixDataResult,
      configCodec: twitchLifecycleConfigCodec,
      invoke: (config, context) {
        if (operation.status == 'RESOLVED' && config.winningOutcomeId == null) {
          throw ArgumentError(
            'winningOutcomeId is required to resolve a prediction.',
          );
        }
        return transport.request('PATCH', '/helix/${operation.path}', {}, {
          'broadcaster_id': _idValue(
            config.broadcasterId,
            context,
            'broadcasterId',
          ),
          'id': config.id,
          'status': operation.status,
          if (operation.status == 'RESOLVED')
            'winning_outcome_id': config.winningOutcomeId,
        });
      },
    ),
  for (final operation in const [
    (id: 'pinMessage', label: 'Pin Chat Message', method: 'PUT'),
    (id: 'unpinMessage', label: 'Unpin Chat Message', method: 'DELETE'),
  ])
    ActionSpec<TwitchPinConfig, RuntimeMap>(
      pluginId: PluginId('twitch'),
      actionId: ActionId(operation.id),
      displayName: operation.label,
      configSchema: _twitchObject(operation.label, [
        ..._identities,
        _twitchText('Message ID', 'messageId', required: true),
        if (operation.method == 'PUT')
          DartDataInputSchema(
            label: 'Duration (30–1800 seconds, empty until stream ends)',
            key: 'duration',
            kind: DartDataInputKind.number,
          ),
      ]),
      configCodec: twitchPinConfigCodec,
      invoke: (config, context) =>
          transport.request(operation.method, '/helix/chat/pins', {
            'broadcaster_id': _idValue(
              config.broadcasterId,
              context,
              'broadcasterId',
            ),
            'moderator_id': _idValue(
              config.moderatorId,
              context,
              'moderatorId',
            ),
            'message_id': config.messageId,
            if (operation.method == 'PUT' && config.duration != null)
              'duration_seconds': config.duration,
          }, {}),
    ),
  for (final operation in const [
    (id: 'addVip', label: 'Add VIP', path: 'channels/vips', method: 'POST'),
    (
      id: 'removeVip',
      label: 'Remove VIP',
      path: 'channels/vips',
      method: 'DELETE',
    ),
    (
      id: 'addModerator',
      label: 'Add Moderator',
      path: 'moderation/moderators',
      method: 'POST',
    ),
    (
      id: 'removeModerator',
      label: 'Remove Moderator',
      path: 'moderation/moderators',
      method: 'DELETE',
    ),
  ])
    ActionSpec<TwitchRoleConfig, RuntimeMap>(
      pluginId: PluginId('twitch'),
      actionId: ActionId(operation.id),
      displayName: operation.label,
      configSchema: _twitchObject(operation.label, [
        _broadcaster,
        _twitchText('Viewer ID', 'viewerId', required: true),
      ]),
      configCodec: twitchRoleConfigCodec,
      invoke: (config, context) =>
          transport.request(operation.method, '/helix/${operation.path}', {
            'broadcaster_id': _idValue(
              config.broadcasterId,
              context,
              'broadcasterId',
            ),
            'user_id': config.viewerId,
          }, {}),
    ),
  ActionSpec<TwitchWarningConfig, RuntimeMap>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('warnUser'),
    displayName: 'Warn Viewer',
    configSchema: _twitchObject('Warn viewer', [
      ..._identities,
      _twitchText('Viewer ID', 'viewerId', required: true),
      _twitchText(
        'Reason (up to 500 characters)',
        'reason',
        required: true,
        multiline: true,
      ),
    ]),
    resultSchema: _helixDataResult,
    configCodec: twitchWarningConfigCodec,
    invoke: (config, context) => transport.request(
      'POST',
      '/helix/moderation/warnings',
      {
        'broadcaster_id': _idValue(
          config.broadcasterId,
          context,
          'broadcasterId',
        ),
        'moderator_id': _idValue(config.moderatorId, context, 'moderatorId'),
      },
      {
        'data': {'user_id': config.viewerId, 'reason': config.reason},
      },
    ),
  ),
  for (final decision in ['ALLOW', 'DENY'])
    ActionSpec<TwitchAutoModDecisionConfig, RuntimeMap>(
      pluginId: PluginId('twitch'),
      actionId: ActionId(
        decision == 'ALLOW' ? 'allowAutoModMessage' : 'denyAutoModMessage',
      ),
      displayName: '${decision == 'ALLOW' ? 'Allow' : 'Deny'} AutoMod Message',
      configSchema: _twitchObject('AutoMod message', [
        _moderator,
        _twitchText('Held message ID', 'messageId', required: true),
      ]),
      configCodec: twitchAutoModDecisionConfigCodec,
      invoke: (config, context) =>
          transport.request('POST', '/helix/moderation/automod/message', {}, {
            'user_id': _idValue(config.moderatorId, context, 'moderatorId'),
            'msg_id': config.messageId,
            'action': decision,
          }),
    ),
];

final _moderationEventSchema = _twitchObject('Moderation event', [
  _twitchText('Viewer ID', 'viewerId'),
  _twitchText('Moderator ID', 'moderatorId'),
  _twitchText('Message ID', 'messageId'),
  _twitchText('Message', 'message'),
  _twitchText('Reason', 'reason'),
  _twitchText('Status', 'status'),
  DartDataInputSchema(
    label: 'Details',
    key: 'details',
    kind: DartDataInputKind.object,
  ),
]);
