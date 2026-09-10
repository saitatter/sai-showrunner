part of '../actions.dart';

List<ActionSpec<Map<String, dynamic>, Object?>> _obsRecordingActions(
  ObsTransport transport,
) => [
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('obs'),
    actionId: ActionId('recordingStartStop'),
    displayName: 'Recording Start/Stop',
    configSchema: _recordingConfigSchema,
    invoke: (config, context) async => _toggle(
      transport,
      _toggleValue(config['recording']),
      'ToggleRecord',
      'StartRecord',
      'StopRecord',
    ),
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('obs'),
    actionId: ActionId('replayBufferStartStop'),
    displayName: 'Replay Buffer Start/Stop',
    configSchema: _replayBufferConfigSchema,
    invoke: (config, context) async => _toggle(
      transport,
      _toggleValue(config['replayBuffer']),
      'ToggleReplayBuffer',
      'StartReplayBuffer',
      'StopReplayBuffer',
    ),
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('obs'),
    actionId: ActionId('replaySave'),
    displayName: 'Save Replay Buffer',
    configSchema: _emptyConfigSchema,
    invoke: (config, context) async {
      await transport.call('SaveReplayBuffer', {});
      final response = await transport.call('GetLastReplayBufferReplay', {});
      return {'replayFile': response['savedReplayPath']};
    },
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('obs'),
    actionId: ActionId('chapterMarker'),
    displayName: 'Chapter Marker',
    configSchema: _chapterConfigSchema,
    invoke: (config, context) => transport.call('CreateRecordChapter', {
      'chapterName': config['chapterName'],
    }),
  ),
  ActionSpec<Map<String, dynamic>, Object?>(
    pluginId: PluginId('obs'),
    actionId: ActionId('screenshot'),
    displayName: 'Screenshot Source',
    configSchema: _screenshotConfigSchema,
    invoke: (config, context) async {
      final directory = config['directory']?.toString().trim() ?? '';
      if (directory.isEmpty) {
        throw ArgumentError('Screenshot directory is required.');
      }
      await Directory(directory).create(recursive: true);
      var filename = config['filename']?.toString().trim() ?? '';
      if (filename.isEmpty) {
        filename = 'screenshot-${DateTime.now().millisecondsSinceEpoch}.png';
      }
      if (!filename.toLowerCase().endsWith('.png')) {
        filename = '$filename.png';
      }
      final filePath = '$directory${Platform.pathSeparator}$filename';
      final request = <String, dynamic>{
        'sourceName': config['sourceName'],
        'imageFormat': 'png',
        'imageFilePath': filePath,
      };
      if (config['width'] is num) request['imageWidth'] = config['width'];
      if (config['height'] is num) {
        request['imageHeight'] = config['height'];
      }
      await transport.call('SaveSourceScreenshot', request);
      return {'screenshot': filePath};
    },
  ),
];
