import 'dart:math' as math;
import 'dart:io';

import '../../components/data_inputs/data_input.dart';
import '../../runtime/expression.dart';
import 'ui/obs_workspace.dart';
import 'transform.dart';
import '../registry/plugin_registry.dart';

typedef ObsCall = Future<RuntimeMap> Function(String request, RuntimeMap data);

const _transformConfigSchema = DartDataInputSchema(
  label: 'Source transform',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Scene',
      key: 'scene',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Source ID',
      key: 'source',
      kind: DartDataInputKind.number,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Transform',
      key: 'transform',
      kind: DartDataInputKind.obsTransform,
      required: true,
    ),
  ],
);

const _emptyConfigSchema = DartDataInputSchema(
  label: 'OBS action',
  kind: DartDataInputKind.object,
);

DartDataInputSchema _objectSchema(
  String label,
  List<DartDataInputSchema> fields,
) => DartDataInputSchema(
  label: label,
  kind: DartDataInputKind.object,
  fields: fields,
);

DartDataInputSchema _toggleConfigSchema({
  required String label,
  required String key,
  required bool defaultValue,
}) => _objectSchema('OBS $label', [
  DartDataInputSchema(
    label: label,
    key: key,
    kind: DartDataInputKind.enumeration,
    options: const ['true', 'false', 'toggle'],
    required: true,
    defaultValue: defaultValue,
  ),
]);

final _streamConfigSchema = _toggleConfigSchema(
  label: 'Streaming',
  key: 'streaming',
  defaultValue: true,
);
final _recordingConfigSchema = _toggleConfigSchema(
  label: 'Recording',
  key: 'recording',
  defaultValue: true,
);
final _virtualCamConfigSchema = _toggleConfigSchema(
  label: 'Virtual camera',
  key: 'virtualCam',
  defaultValue: true,
);
final _replayBufferConfigSchema = _toggleConfigSchema(
  label: 'Replay buffer',
  key: 'replayBuffer',
  defaultValue: true,
);
final _studioModeConfigSchema = _toggleConfigSchema(
  label: 'Studio mode',
  key: 'studioMode',
  defaultValue: true,
);

final _muteConfigSchema = _objectSchema('OBS mute source', const [
  DartDataInputSchema(
    label: 'Source',
    key: 'source',
    kind: DartDataInputKind.text,
    required: true,
  ),
  DartDataInputSchema(
    label: 'Muted',
    key: 'muted',
    kind: DartDataInputKind.enumeration,
    options: ['true', 'false', 'toggle'],
    required: true,
    defaultValue: true,
  ),
]);

final _volumeConfigSchema = _objectSchema('OBS source volume', const [
  DartDataInputSchema(
    label: 'Source',
    key: 'source',
    kind: DartDataInputKind.text,
    required: true,
  ),
  DartDataInputSchema(
    label: 'Volume (0-100)',
    key: 'volume',
    kind: DartDataInputKind.number,
    required: true,
    defaultValue: 100,
  ),
]);

final _sourceVisibilityConfigSchema = _objectSchema(
  'OBS source visibility',
  const [
    DartDataInputSchema(
      label: 'Scene',
      key: 'scene',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Source ID',
      key: 'source',
      kind: DartDataInputKind.number,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Visible',
      key: 'enabled',
      kind: DartDataInputKind.enumeration,
      options: ['true', 'false', 'toggle'],
      required: true,
      defaultValue: true,
    ),
  ],
);

final _filterConfigSchema = _objectSchema('OBS filter visibility', const [
  DartDataInputSchema(
    label: 'Source name',
    key: 'sourceName',
    kind: DartDataInputKind.text,
    required: true,
  ),
  DartDataInputSchema(
    label: 'Filter name',
    key: 'filterName',
    kind: DartDataInputKind.text,
    required: true,
  ),
  DartDataInputSchema(
    label: 'Enabled',
    key: 'filterEnabled',
    kind: DartDataInputKind.enumeration,
    options: ['true', 'false', 'toggle'],
    required: true,
    defaultValue: true,
  ),
]);

final _textConfigSchema = _objectSchema('OBS source text', const [
  DartDataInputSchema(
    label: 'Source name',
    key: 'sourceName',
    kind: DartDataInputKind.text,
    required: true,
  ),
  DartDataInputSchema(
    label: 'Text',
    key: 'text',
    kind: DartDataInputKind.multilineText,
    required: true,
  ),
]);

final _mediaActionConfigSchema = _objectSchema('OBS media action', const [
  DartDataInputSchema(
    label: 'Source',
    key: 'source',
    kind: DartDataInputKind.text,
    required: true,
  ),
  DartDataInputSchema(
    label: 'Media action',
    key: 'action',
    kind: DartDataInputKind.enumeration,
    options: ['Play', 'Pause', 'Restart', 'Stop', 'Next', 'Previous'],
    required: true,
    defaultValue: 'Play',
  ),
]);

final _playMediaConfigSchema = _objectSchema('OBS play media', const [
  DartDataInputSchema(
    label: 'Scene',
    key: 'scene',
    kind: DartDataInputKind.text,
    required: true,
  ),
  DartDataInputSchema(
    label: 'Source ID',
    key: 'source',
    kind: DartDataInputKind.number,
    required: true,
  ),
]);

final _chapterConfigSchema = _objectSchema('OBS chapter marker', const [
  DartDataInputSchema(
    label: 'Chapter name',
    key: 'chapterName',
    kind: DartDataInputKind.text,
  ),
]);

final _browserUrlConfigSchema = _objectSchema('OBS browser URL', const [
  DartDataInputSchema(
    label: 'Source',
    key: 'source',
    kind: DartDataInputKind.text,
    required: true,
  ),
  DartDataInputSchema(
    label: 'URL',
    key: 'url',
    kind: DartDataInputKind.text,
    required: true,
  ),
]);

final _browserRefreshConfigSchema = _objectSchema('OBS browser refresh', const [
  DartDataInputSchema(
    label: 'Source',
    key: 'source',
    kind: DartDataInputKind.text,
    required: true,
  ),
]);

final _refreshBrowserConfigSchema = _objectSchema('OBS browser refresh', const [
  DartDataInputSchema(
    label: 'Source name',
    key: 'sourceName',
    kind: DartDataInputKind.text,
    required: true,
  ),
]);

final _setBrowserUrlConfigSchema =
    _objectSchema('OBS browser source URL', const [
      DartDataInputSchema(
        label: 'Source name',
        key: 'sourceName',
        kind: DartDataInputKind.text,
        required: true,
      ),
      DartDataInputSchema(
        label: 'URL',
        key: 'url',
        kind: DartDataInputKind.text,
        required: true,
      ),
    ]);

final _setImageConfigSchema = _objectSchema('OBS image source', const [
  DartDataInputSchema(
    label: 'Source name',
    key: 'sourceName',
    kind: DartDataInputKind.text,
    required: true,
  ),
  DartDataInputSchema(
    label: 'Image',
    key: 'image',
    kind: DartDataInputKind.filePath,
    required: true,
  ),
]);

final _screenshotConfigSchema = _objectSchema('OBS screenshot', const [
  DartDataInputSchema(
    label: 'Source name',
    key: 'sourceName',
    kind: DartDataInputKind.text,
  ),
  DartDataInputSchema(
    label: 'Width',
    key: 'width',
    kind: DartDataInputKind.number,
  ),
  DartDataInputSchema(
    label: 'Height',
    key: 'height',
    kind: DartDataInputKind.number,
  ),
  DartDataInputSchema(
    label: 'Directory',
    key: 'directory',
    kind: DartDataInputKind.filePath,
    required: true,
  ),
  DartDataInputSchema(
    label: 'Filename',
    key: 'filename',
    kind: DartDataInputKind.text,
    required: true,
    defaultValue: 'screenshot.png',
  ),
]);

final class ObsConnectionConfig {
  const ObsConnectionConfig({
    required this.name,
    required this.host,
    required this.port,
    required this.local,
    this.password,
  });

  final String name;
  final String host;
  final int port;
  final bool local;
  final String? password;
}

abstract interface class ObsTransport {
  Future<RuntimeMap> call(String request, RuntimeMap data);
}

final class CallbackObsTransport implements ObsTransport {
  const CallbackObsTransport(this._callback);

  final ObsCall _callback;

  @override
  Future<RuntimeMap> call(String request, RuntimeMap data) =>
      _callback(request, data);
}

DartPluginManifest createObsPlugin(ObsTransport transport) {
  final previousScenes = <String>[];
  return DartPluginManifest(
    id: 'obs',
    name: 'OBS Studio',
    healthCheck: () async {
      await transport.call('GetVersion', {});
      return true;
    },
    workspaceBuilder: (context, dataService, providerEvents, registryFuture) =>
        ObsWorkspace(dataService: dataService, registryFuture: registryFuture),
    states: const [
      DartPluginStateDefinition(
        id: 'connection',
        displayName: 'Connection',
        initialValue: 'unconfigured',
      ),
      DartPluginStateDefinition(
        id: 'localObsRunning',
        displayName: 'Local OBS Running',
        initialValue: false,
      ),
    ],
    settings: const [
      DartSettingDefinition(
        id: 'obsDefault',
        displayName: 'Default OBS Connection',
      ),
      DartSettingDefinition(
        id: 'host',
        displayName: 'Host',
        defaultValue: '127.0.0.1',
      ),
      DartSettingDefinition(
        id: 'port',
        displayName: 'Port',
        defaultValue: 4455,
      ),
      DartSettingDefinition(
        id: 'password',
        displayName: 'Password',
        secret: true,
      ),
    ],
    actions: [
      DartActionDefinition(
        pluginId: 'obs',
        actionId: 'scene',
        displayName: 'Change Scene',
        configSchema: const DartDataInputSchema(
          label: 'Scene configuration',
          kind: DartDataInputKind.object,
          fields: [
            DartDataInputSchema(
              label: 'Scene',
              key: 'scene',
              kind: DartDataInputKind.text,
              required: true,
            ),
          ],
        ),
        invoke: (config, context) async {
          final scene = config['scene']?.toString();
          if (scene == null || scene.isEmpty) return null;
          final current = await transport.call('GetCurrentProgramScene', {});
          final currentScene = current['currentProgramSceneName']?.toString();
          if (currentScene != null &&
              currentScene.isNotEmpty &&
              currentScene != scene) {
            previousScenes.add(currentScene);
          }
          await transport.call('SetCurrentProgramScene', {'sceneName': scene});
          return null;
        },
      ),
      DartActionDefinition(
        pluginId: 'obs',
        actionId: 'prevScene',
        displayName: 'Previous Scene',
        configSchema: _emptyConfigSchema,
        invoke: (config, context) async {
          if (previousScenes.isEmpty) return null;
          final scene = previousScenes.removeLast();
          await transport.call('SetCurrentProgramScene', {'sceneName': scene});
          return {'scene': scene};
        },
      ),
      DartActionDefinition(
        pluginId: 'obs',
        actionId: 'hotkey',
        displayName: 'Hotkey',
        configSchema: const DartDataInputSchema(
          label: 'Hotkey configuration',
          kind: DartDataInputKind.object,
          fields: [
            DartDataInputSchema(
              label: 'hotkey',
              kind: DartDataInputKind.text,
              required: true,
            ),
          ],
        ),
        invoke: (config, context) => transport.call('TriggerHotkeyByName', {
          'hotkeyName': config['hotkey'],
        }),
      ),
      DartActionDefinition(
        pluginId: 'obs',
        actionId: 'streamStartStop',
        displayName: 'Stream Start/Stop',
        configSchema: _streamConfigSchema,
        invoke: (config, context) async => _toggle(
          transport,
          _toggleValue(config['streaming']),
          'ToggleStream',
          'StartStream',
          'StopStream',
        ),
      ),
      DartActionDefinition(
        pluginId: 'obs',
        actionId: 'recordingStartStop',
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
      DartActionDefinition(
        pluginId: 'obs',
        actionId: 'virtualCamStartStop',
        displayName: 'Virtual Cam Start/Stop',
        configSchema: _virtualCamConfigSchema,
        invoke: (config, context) async => _toggle(
          transport,
          _toggleValue(config['virtualCam']),
          'ToggleVirtualCam',
          'StartVirtualCam',
          'StopVirtualCam',
        ),
      ),
      DartActionDefinition(
        pluginId: 'obs',
        actionId: 'replayBufferStartStop',
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
      DartActionDefinition(
        pluginId: 'obs',
        actionId: 'replaySave',
        displayName: 'Save Replay Buffer',
        configSchema: _emptyConfigSchema,
        invoke: (config, context) async {
          await transport.call('SaveReplayBuffer', {});
          final response = await transport.call(
            'GetLastReplayBufferReplay',
            {},
          );
          return {'replayFile': response['savedReplayPath']};
        },
      ),
      DartActionDefinition(
        pluginId: 'obs',
        actionId: 'toggleStudioMode',
        displayName: 'Toggle Studio Mode',
        configSchema: _studioModeConfigSchema,
        invoke: (config, context) async {
          var enabled = _toggleValue(config['studioMode']);
          if (enabled == 'toggle') {
            enabled = !(config['studioModeEnabled'] == true);
          }
          return transport.call('SetStudioModeEnabled', {
            'studioModeEnabled': enabled == true,
          });
        },
      ),
      DartActionDefinition(
        pluginId: 'obs',
        actionId: 'triggerStudioModeTransition',
        displayName: 'Trigger Studio Mode Transition',
        configSchema: _emptyConfigSchema,
        invoke: (config, context) =>
            transport.call('TriggerStudioModeTransition', {}),
      ),
      DartActionDefinition(
        pluginId: 'obs',
        actionId: 'mute',
        displayName: 'Mute Source',
        configSchema: _muteConfigSchema,
        invoke: (config, context) async {
          var muted = _toggleValue(config['muted']);
          if (muted == 'toggle') {
            final status = await transport.call('GetInputMute', {
              'inputName': config['source'],
            });
            muted = !(status['inputMuted'] == true);
          }
          await transport.call('SetInputMute', {
            'inputName': config['source'],
            'inputMuted': muted == true,
          });
          return {'audioMuted': muted == true};
        },
      ),
      DartActionDefinition(
        pluginId: 'obs',
        actionId: 'changeVolume',
        displayName: 'Change Volume',
        configSchema: _volumeConfigSchema,
        invoke: (config, context) => transport.call('SetInputVolume', {
          'inputName': config['source'],
          'inputVolumeDb': _sliderToDb(config['volume']),
        }),
      ),
      DartActionDefinition(
        pluginId: 'obs',
        actionId: 'source',
        displayName: 'Source Visibility',
        configSchema: _sourceVisibilityConfigSchema,
        invoke: (config, context) async {
          var enabled = _toggleValue(config['enabled']);
          if (enabled == 'toggle') {
            final response = await transport.call('GetSceneItemEnabled', {
              'sceneName': config['scene'],
              'sceneItemId': config['source'],
            });
            enabled = !(response['sceneItemEnabled'] == true);
          }
          await transport.call('SetSceneItemEnabled', {
            'sceneName': config['scene'],
            'sceneItemId': config['source'],
            'sceneItemEnabled': enabled == true,
          });
          return {'sourceEnabled': enabled == true};
        },
      ),
      DartActionDefinition(
        pluginId: 'obs',
        actionId: 'getInputSettings',
        displayName: 'Get Input Settings',
        configSchema: const DartDataInputSchema(
          label: 'Input settings query',
          kind: DartDataInputKind.object,
          fields: [
            DartDataInputSchema(
              label: 'Source name',
              key: 'sourceName',
              kind: DartDataInputKind.text,
              required: true,
            ),
          ],
        ),
        invoke: (config, context) => transport.call('GetInputSettings', {
          'inputName': config['sourceName'],
        }),
      ),
      DartActionDefinition(
        pluginId: 'obs',
        actionId: 'setInputSettings',
        displayName: 'Set Input Settings',
        configSchema: const DartDataInputSchema(
          label: 'Input settings',
          kind: DartDataInputKind.object,
          fields: [
            DartDataInputSchema(
              label: 'Source name',
              key: 'sourceName',
              kind: DartDataInputKind.text,
              required: true,
            ),
            DartDataInputSchema(
              label: 'Input settings',
              key: 'inputSettings',
              kind: DartDataInputKind.object,
              required: true,
            ),
          ],
        ),
        invoke: (config, context) => transport.call('SetInputSettings', {
          'inputName': config['sourceName'],
          'inputSettings': config['inputSettings'],
        }),
      ),
      DartActionDefinition(
        pluginId: 'obs',
        actionId: 'filter',
        displayName: 'Filter Visibility',
        configSchema: _filterConfigSchema,
        invoke: (config, context) async {
          var enabled = _toggleValue(config['filterEnabled']);
          if (enabled == 'toggle') {
            final response = await transport.call('GetSourceFilter', {
              'sourceName': config['sourceName'],
              'filterName': config['filterName'],
            });
            enabled = !(response['filterEnabled'] == true);
          }
          await transport.call('SetSourceFilterEnabled', {
            'sourceName': config['sourceName'],
            'filterName': config['filterName'],
            'filterEnabled': enabled == true,
          });
          return {'filterEnabled': enabled == true};
        },
      ),
      DartActionDefinition(
        pluginId: 'obs',
        actionId: 'text',
        displayName: 'Set Source Text',
        configSchema: _textConfigSchema,
        invoke: (config, context) => transport.call('SetInputSettings', {
          'inputName': config['sourceName'],
          'inputSettings': {'text': config['text']},
        }),
      ),
      DartActionDefinition(
        pluginId: 'obs',
        actionId: 'mediaAction',
        displayName: 'Media Controls',
        configSchema: _mediaActionConfigSchema,
        invoke: (config, context) => transport.call('TriggerMediaInputAction', {
          'inputName': config['source'],
          'mediaAction': _mediaAction(config['action']),
        }),
      ),
      DartActionDefinition(
        pluginId: 'obs',
        actionId: 'playMedia',
        displayName: 'Play Media',
        configSchema: _playMediaConfigSchema,
        invoke: (config, context) async {
          final sceneName = config['scene'];
          final sceneItemId = config['source'];
          if (sceneName == null || sceneItemId == null) return null;
          final enabled = await transport.call('GetSceneItemEnabled', {
            'sceneName': sceneName,
            'sceneItemId': sceneItemId,
          });
          if (enabled['sceneItemEnabled'] != true) {
            await transport.call('SetSceneItemEnabled', {
              'sceneName': sceneName,
              'sceneItemId': sceneItemId,
              'sceneItemEnabled': true,
            });
          }
          await transport.call('TriggerMediaInputAction', {
            'inputName': config['sourceName'] ?? config['source'],
            'mediaAction': 'OBS_WEBSOCKET_MEDIA_INPUT_ACTION_RESTART',
          });
          return {'playing': true};
        },
      ),
      DartActionDefinition(
        pluginId: 'obs',
        actionId: 'chapterMarker',
        displayName: 'Chapter Marker',
        configSchema: _chapterConfigSchema,
        invoke: (config, context) => transport.call('CreateRecordChapter', {
          'chapterName': config['chapterName'],
        }),
      ),
      DartActionDefinition(
        pluginId: 'obs',
        actionId: 'browserUrl',
        displayName: 'Set Browser Source URL',
        configSchema: _browserUrlConfigSchema,
        invoke: (config, context) async {
          await transport.call('SetInputSettings', {
            'inputName': config['source'],
            'inputSettings': {'url': config['url']},
            'overlay': true,
          });
          return null;
        },
      ),
      DartActionDefinition(
        pluginId: 'obs',
        actionId: 'browserRefresh',
        displayName: 'Refresh Browser Source',
        configSchema: _browserRefreshConfigSchema,
        invoke: (config, context) async {
          await transport.call('PressInputPropertiesButton', {
            'inputName': config['source'],
            'propertyName': 'refreshnocache',
          });
          return null;
        },
      ),
      DartActionDefinition(
        pluginId: 'obs',
        actionId: 'refreshBrowser',
        displayName: 'Refresh Browser',
        configSchema: _refreshBrowserConfigSchema,
        invoke: (config, context) => transport.call(
          'PressInputPropertiesButton',
          {'inputName': config['sourceName'], 'propertyName': 'refreshnocache'},
        ),
      ),
      DartActionDefinition(
        pluginId: 'obs',
        actionId: 'setBrowserURL',
        displayName: 'Set Browser URL',
        configSchema: _setBrowserUrlConfigSchema,
        invoke: (config, context) => transport.call('SetInputSettings', {
          'inputName': config['sourceName'],
          'inputSettings': {'url': config['url']},
        }),
      ),
      DartActionDefinition(
        pluginId: 'obs',
        actionId: 'setImage',
        displayName: 'Set Image Source',
        configSchema: _setImageConfigSchema,
        invoke: (config, context) => transport.call('SetInputSettings', {
          'inputName': config['sourceName'],
          'inputSettings': {'file': config['image']},
        }),
      ),
      DartActionDefinition(
        pluginId: 'obs',
        actionId: 'screenshot',
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
            filename =
                'screenshot-${DateTime.now().millisecondsSinceEpoch}.png';
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
      DartActionDefinition(
        pluginId: 'obs',
        actionId: 'transform',
        displayName: 'Source Transform',
        configSchema: _transformConfigSchema,
        invoke: (config, context) => transport.call('SetSceneItemTransform', {
          'sceneName': config['scene'],
          'sceneItemId': config['source'],
          'sceneItemTransform': obsTransformToWebSocket(config['transform']),
        }),
      ),
    ],
  );
}

String _mediaAction(dynamic action) => switch (action) {
  'Play' => 'OBS_WEBSOCKET_MEDIA_INPUT_ACTION_PLAY',
  'Pause' => 'OBS_WEBSOCKET_MEDIA_INPUT_ACTION_PAUSE',
  'Restart' => 'OBS_WEBSOCKET_MEDIA_INPUT_ACTION_RESTART',
  'Stop' => 'OBS_WEBSOCKET_MEDIA_INPUT_ACTION_STOP',
  'Next' => 'OBS_WEBSOCKET_MEDIA_INPUT_ACTION_NEXT',
  'Previous' => 'OBS_WEBSOCKET_MEDIA_INPUT_ACTION_PREVIOUS',
  _ => 'OBS_WEBSOCKET_MEDIA_INPUT_ACTION_PLAY',
};

double _sliderToDb(dynamic value) {
  final slider =
      ((value is num ? value.toDouble() : double.tryParse('$value') ?? 0) / 100)
          .clamp(0, 1)
          .toDouble();
  if (slider == 1) return 0;
  if (slider <= 0) return -100;
  const offset = 6;
  const range = 96;
  return -(range + offset) *
          math.pow((range + offset) / offset, -slider).toDouble() +
      offset;
}

dynamic _toggleValue(dynamic value) => value is String
    ? switch (value.toLowerCase()) {
        'true' => true,
        'false' => false,
        _ => value,
      }
    : value;

Future<Object?> _toggle(
  ObsTransport transport,
  dynamic value,
  String toggle,
  String start,
  String stop,
) {
  final request = value == 'toggle'
      ? toggle
      : value == true
      ? start
      : stop;
  return transport.call(request, {});
}
