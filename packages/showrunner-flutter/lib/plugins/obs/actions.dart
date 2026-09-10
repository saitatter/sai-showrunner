import 'dart:math' as math;
import 'dart:io';

import '../../schema/data_input.dart';
import '../../runtime/expression.dart';
import 'transform.dart';
import '../registry/plugin_contract.dart';

part 'actions/scenes.dart';
part 'actions/sources.dart';
part 'actions/audio.dart';
part 'actions/browser.dart';
part 'actions/recording.dart';
part 'actions/streaming.dart';

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

  Future<void> close();
}

final class CallbackObsTransport implements ObsTransport {
  const CallbackObsTransport(this._callback);

  final ObsCall _callback;

  @override
  Future<RuntimeMap> call(String request, RuntimeMap data) =>
      _callback(request, data);

  @override
  Future<void> close() async {}
}

DartPluginManifest createObsPlugin(ObsTransport transport) {
  final previousScenes = <String>[];
  final sceneActions = _obsSceneActions(transport, previousScenes);
  final sourceActions = _obsSourceActions(transport);
  final audioActions = _obsAudioActions(transport);
  final browserActions = _obsBrowserActions(transport);
  final recordingActions = _obsRecordingActions(transport);
  final streamingActions = _obsStreamingActions(transport);
  return DartPluginManifest(
    id: PluginId('obs'),
    name: 'OBS Studio',
    states: const [
      StateSpec(
        id: StateId('connection'),
        displayName: 'Connection',
        initialValue: 'unconfigured',
      ),
      StateSpec(
        id: StateId('connected'),
        displayName: 'Connected',
        initialValue: false,
      ),
      StateSpec(id: StateId('scene'), displayName: 'Scene'),
      StateSpec(
        id: StateId('streaming'),
        displayName: 'Streaming',
        initialValue: false,
      ),
      StateSpec(
        id: StateId('recording'),
        displayName: 'Recording',
        initialValue: false,
      ),
      StateSpec(
        id: StateId('localObsRunning'),
        displayName: 'Local OBS Running',
        initialValue: false,
      ),
    ],
    settings: const [
      SettingSpec(
        id: SettingId('obsDefault'),
        displayName: 'Default OBS Connection',
      ),
      SettingSpec(
        id: SettingId('host'),
        displayName: 'Host',
        defaultValue: '127.0.0.1',
      ),
      SettingSpec(
        id: SettingId('port'),
        displayName: 'Port',
        defaultValue: 4455,
      ),
      SettingSpec(
        id: SettingId('password'),
        displayName: 'Password',
        secret: true,
      ),
    ],
    actions: [
      _obsAction(sceneActions, 'scene'),
      _obsAction(sceneActions, 'prevScene'),
      _obsAction(streamingActions, 'hotkey'),
      _obsAction(streamingActions, 'streamStartStop'),
      _obsAction(recordingActions, 'recordingStartStop'),
      _obsAction(streamingActions, 'virtualCamStartStop'),
      _obsAction(recordingActions, 'replayBufferStartStop'),
      _obsAction(recordingActions, 'replaySave'),
      _obsAction(streamingActions, 'toggleStudioMode'),
      _obsAction(streamingActions, 'triggerStudioModeTransition'),
      _obsAction(audioActions, 'mute'),
      _obsAction(audioActions, 'changeVolume'),
      _obsAction(sourceActions, 'source'),
      _obsAction(sourceActions, 'getInputSettings'),
      _obsAction(sourceActions, 'setInputSettings'),
      _obsAction(sourceActions, 'filter'),
      _obsAction(sourceActions, 'text'),
      _obsAction(sourceActions, 'mediaAction'),
      _obsAction(sourceActions, 'playMedia'),
      _obsAction(recordingActions, 'chapterMarker'),
      _obsAction(browserActions, 'browserUrl'),
      _obsAction(browserActions, 'browserRefresh'),
      _obsAction(browserActions, 'refreshBrowser'),
      _obsAction(browserActions, 'setBrowserURL'),
      _obsAction(sourceActions, 'setImage'),
      _obsAction(recordingActions, 'screenshot'),
      _obsAction(sourceActions, 'transform'),
    ],
  );
}

ActionSpec<Map<String, dynamic>, Object?> _obsAction(
  List<ActionSpec<Map<String, dynamic>, Object?>> actions,
  String id,
) => actions.firstWhere((action) => action.actionId.value == id);

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
