part of '../actions.dart';

List<DartActionContract> _obsRecordingActions(ObsTransport transport) => [
  ActionSpec<ObsToggleConfig, RuntimeMap>(
    pluginId: PluginId('obs'),
    actionId: ActionId('recordingStartStop'),
    displayName: 'Recording Start/Stop',
    configSchema: _recordingConfigSchema,
    configCodec: obsToggleConfigCodec('recording'),
    invoke: (config, context) async => _toggle(
      transport,
      config.mode,
      'ToggleRecord',
      'StartRecord',
      'StopRecord',
    ),
  ),
  ActionSpec<ObsToggleConfig, RuntimeMap>(
    pluginId: PluginId('obs'),
    actionId: ActionId('replayBufferStartStop'),
    displayName: 'Replay Buffer Start/Stop',
    configSchema: _replayBufferConfigSchema,
    configCodec: obsToggleConfigCodec('replayBuffer'),
    invoke: (config, context) async => _toggle(
      transport,
      config.mode,
      'ToggleReplayBuffer',
      'StartReplayBuffer',
      'StopReplayBuffer',
    ),
  ),
  ActionSpec<ObsEmptyConfig, RuntimeMap>(
    pluginId: PluginId('obs'),
    actionId: ActionId('replaySave'),
    displayName: 'Save Replay Buffer',
    configSchema: _emptyConfigSchema,
    configCodec: obsEmptyConfigCodec,
    invoke: (config, context) async {
      await transport.call('SaveReplayBuffer', {});
      final response = await transport.call('GetLastReplayBufferReplay', {});
      return {'replayFile': response['savedReplayPath']};
    },
  ),
  ActionSpec<ObsChapterMarkerConfig, RuntimeMap>(
    pluginId: PluginId('obs'),
    actionId: ActionId('chapterMarker'),
    displayName: 'Chapter Marker',
    configSchema: _chapterConfigSchema,
    configCodec: obsChapterMarkerConfigCodec,
    invoke: (config, context) => transport.call('CreateRecordChapter', {
      'chapterName': config.chapterName,
    }),
  ),
  ActionSpec<ObsScreenshotConfig, RuntimeMap>(
    pluginId: PluginId('obs'),
    actionId: ActionId('screenshot'),
    displayName: 'Screenshot Source',
    configSchema: _screenshotConfigSchema,
    configCodec: obsScreenshotConfigCodec,
    invoke: (config, context) async {
      final directory = config.directory?.trim() ?? '';
      if (directory.isEmpty) {
        throw ArgumentError('Screenshot directory is required.');
      }
      await Directory(directory).create(recursive: true);
      var filename = config.filename?.trim() ?? '';
      if (filename.isEmpty) {
        filename = 'screenshot-${DateTime.now().millisecondsSinceEpoch}.png';
      }
      if (!filename.toLowerCase().endsWith('.png')) {
        filename = '$filename.png';
      }
      final filePath = '$directory${Platform.pathSeparator}$filename';
      final request = <String, dynamic>{
        'sourceName': config.sourceName,
        'imageFormat': 'png',
        'imageFilePath': filePath,
      };
      if (config.width != null) request['imageWidth'] = config.width;
      if (config.height != null) {
        request['imageHeight'] = config.height;
      }
      await transport.call('SaveSourceScreenshot', request);
      return {'screenshot': filePath};
    },
  ),
];
