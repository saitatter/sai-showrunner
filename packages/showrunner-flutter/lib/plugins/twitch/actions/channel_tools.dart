part of '../actions.dart';

List<DartActionContract> _twitchChannelToolActions(
  TwitchTransport transport,
) => [
  ActionSpec<TwitchBroadcasterConfig, RuntimeMap>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('getChannelTags'),
    displayName: 'Get Channel Tags',
    configSchema: _twitchObject('Get channel tags', [_broadcaster]),
    configCodec: twitchBroadcasterConfigCodec,
    resultSchema: _twitchObject('Channel tags', [
      DartDataInputSchema(
        label: 'Tags',
        key: 'tags',
        kind: DartDataInputKind.array,
      ),
    ]),
    invoke: (config, context) async {
      final result = await transport.request('GET', '/helix/channels', {
        'broadcaster_id': _idValue(
          config.broadcasterId,
          context,
          'broadcasterId',
        ),
      }, {});
      final data = result['data'];
      if (data is! List ||
          data.length != 1 ||
          data.single is! Map ||
          (data.single as Map)['tags'] is! List) {
        throw StateError('Twitch did not return channel tags.');
      }
      final tags = (data.single as Map)['tags'] as List;
      if (tags.any((tag) => tag is! String)) {
        throw StateError('Twitch returned invalid channel tags.');
      }
      return {'tags': tags.cast<String>().toList()};
    },
  ),
  ActionSpec<TwitchTagsConfig, RuntimeMap>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('setChannelTags'),
    displayName: 'Set Channel Tags',
    configSchema: _twitchObject('Replace channel tags (empty list clears)', [
      _broadcaster,
      DartDataInputSchema(
        label: 'Tags (up to 10)',
        key: 'tags',
        kind: DartDataInputKind.array,
        required: true,
      ),
    ]),
    configCodec: twitchTagsConfigCodec,
    invoke: (config, context) => transport.request(
      'PATCH',
      '/helix/channels',
      {
        'broadcaster_id': _idValue(
          config.broadcasterId,
          context,
          'broadcasterId',
        ),
      },
      {'tags': config.tags},
    ),
  ),
  ActionSpec<TwitchClipDownloadsConfig, RuntimeMap>(
    pluginId: PluginId('twitch'),
    actionId: ActionId('getClipDownloadUrls'),
    displayName: 'Get Clip Download URLs',
    configSchema: _twitchObject('Clip download URLs', [
      _broadcaster,
      _twitchText('Editor ID (authenticated account)', 'editorId'),
      DartDataInputSchema(
        label: 'Clip IDs (1–10)',
        key: 'clipIds',
        kind: DartDataInputKind.array,
        required: true,
      ),
    ]),
    resultSchema: _helixDataResult,
    configCodec: twitchClipDownloadsConfigCodec,
    invoke: (config, context) =>
        transport.request('GET', '/helix/clips/downloads', {
          'broadcaster_id': _idValue(
            config.broadcasterId,
            context,
            'broadcasterId',
          ),
          'editor_id': _idValue(config.editorId, context, 'moderatorId'),
          'clip_id': config.clipIds,
        }, {}),
  ),
  for (final operation in const [
    (
      id: 'getGuestStarSession',
      label: 'Get Guest Star Session',
      path: 'session',
      method: 'GET',
    ),
    (
      id: 'createGuestStarSession',
      label: 'Create Guest Star Session',
      path: 'session',
      method: 'POST',
    ),
    (
      id: 'endGuestStarSession',
      label: 'End Guest Star Session',
      path: 'session',
      method: 'DELETE',
    ),
    (
      id: 'getGuestStarInvites',
      label: 'Get Guest Star Invites',
      path: 'invites',
      method: 'GET',
    ),
    (
      id: 'sendGuestStarInvite',
      label: 'Send Guest Star Invite',
      path: 'invites',
      method: 'POST',
    ),
    (
      id: 'deleteGuestStarInvite',
      label: 'Delete Guest Star Invite',
      path: 'invites',
      method: 'DELETE',
    ),
    (
      id: 'assignGuestStarSlot',
      label: 'Assign Guest Star Slot',
      path: 'slot',
      method: 'POST',
    ),
    (
      id: 'deleteGuestStarSlot',
      label: 'Delete Guest Star Slot',
      path: 'slot',
      method: 'DELETE',
    ),
  ])
    ActionSpec<TwitchGuestStarConfig, RuntimeMap>(
      pluginId: PluginId('twitch'),
      actionId: ActionId(operation.id),
      displayName: operation.label,
      configSchema: _twitchObject(operation.label, [
        _broadcaster,
        if (operation.path != 'session' || operation.method == 'GET')
          _moderator,
        if (operation.path != 'session' || operation.method == 'DELETE')
          _twitchText('Session ID', 'sessionId', required: true),
        if (operation.path == 'slot' ||
            (operation.path == 'invites' && operation.method != 'GET'))
          _twitchText('Guest ID', 'guestId', required: true),
        if (operation.path == 'slot')
          _twitchText('Slot ID (1–6)', 'slotId', required: true),
        if (operation.id == 'deleteGuestStarSlot')
          DartDataInputSchema(
            label: 'Reinvite guest',
            key: 'reinvite',
            kind: DartDataInputKind.boolean,
            defaultValue: false,
          ),
      ]),
      resultSchema:
          operation.method == 'GET' || operation.id == 'createGuestStarSession'
          ? _helixDataResult
          : null,
      configCodec: twitchGuestStarConfigCodec,
      invoke: (config, context) {
        final needsSession =
            operation.path != 'session' || operation.method == 'DELETE';
        final needsGuest =
            operation.path == 'slot' ||
            (operation.path == 'invites' && operation.method != 'GET');
        if (needsSession && config.sessionId == null) {
          throw ArgumentError('sessionId is required.');
        }
        if (needsGuest && config.guestId == null) {
          throw ArgumentError('guestId is required.');
        }
        if (operation.path == 'slot' && config.slotId == null) {
          throw ArgumentError('slotId is required.');
        }
        return transport
            .request(operation.method, '/helix/guest_star/${operation.path}', {
              'broadcaster_id': _idValue(
                config.broadcasterId,
                context,
                'broadcasterId',
              ),
              if (operation.path != 'session' || operation.method == 'GET')
                'moderator_id': _idValue(
                  config.moderatorId,
                  context,
                  'moderatorId',
                ),
              if (needsSession) 'session_id': config.sessionId,
              if (needsGuest) 'guest_id': config.guestId,
              if (operation.path == 'slot') 'slot_id': config.slotId,
              if (operation.id == 'deleteGuestStarSlot')
                'should_reinvite_guest': config.reinvite,
            }, {});
      },
    ),
];
