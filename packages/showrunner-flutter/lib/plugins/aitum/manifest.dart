import '../../schema/data_input.dart';
import '../../runtime/expression.dart';
import '../obs/actions.dart';
import '../registry/plugin_contract.dart';
import 'contracts.dart';

const _vendorName = 'aitum-vertical-canvas';

const _sceneSchema = DartDataInputSchema(
  label: 'Aitum vertical scene',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Scene',
      key: 'scene',
      kind: DartDataInputKind.text,
      required: true,
    ),
  ],
);

const _toggleSchema = DartDataInputSchema(
  label: 'Aitum vertical control',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'State',
      key: 'streaming',
      kind: DartDataInputKind.enumeration,
      options: ['true', 'false', 'toggle'],
      defaultValue: 'true',
    ),
  ],
);

const _chapterSchema = DartDataInputSchema(
  label: 'Aitum chapter marker',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Chapter name',
      key: 'chapterName',
      kind: DartDataInputKind.text,
    ),
  ],
);

DartPluginManifest createAitumPlugin(
  ObsTransport transport,
) => DartPluginManifest(
  id: PluginId('aitum'),
  name: 'Aitum',
  settings: const [
    SettingSpec(id: SettingId('obsConnection'), displayName: 'OBS Connection'),
  ],
  actions: [
    ActionSpec<AitumSceneConfig, RuntimeMap>(
      pluginId: PluginId('aitum'),
      actionId: ActionId('verticalScene'),
      displayName: 'Change Vertical Scene',
      configSchema: _sceneSchema,
      configCodec: aitumSceneConfigCodec,
      invoke: (config, context) =>
          _call(transport, 'switch_scene', {'scene': config.scene}),
    ),
    ActionSpec<AitumToggleConfig, RuntimeMap>(
      pluginId: PluginId('aitum'),
      actionId: ActionId('verticalStreamStartStop'),
      displayName: 'Vertical Stream Start/Stop',
      configSchema: _toggleSchema,
      configCodec: aitumToggleConfigCodec,
      invoke: (config, context) => _toggle(transport, config.mode, 'streaming'),
    ),
    ActionSpec<AitumToggleConfig, RuntimeMap>(
      pluginId: PluginId('aitum'),
      actionId: ActionId('verticalRecordingStartStop'),
      displayName: 'Vertical Recording Start/Stop',
      configSchema: _toggleSchema,
      configCodec: aitumToggleConfigCodec,
      invoke: (config, context) => _toggle(transport, config.mode, 'recording'),
    ),
    ActionSpec<AitumToggleConfig, RuntimeMap>(
      pluginId: PluginId('aitum'),
      actionId: ActionId('verticalBacktrackStartStop'),
      displayName: 'Vertical Backtrack Start/Stop',
      configSchema: _toggleSchema,
      configCodec: aitumToggleConfigCodec,
      invoke: (config, context) => _toggle(transport, config.mode, 'backtrack'),
    ),
    ActionSpec<AitumEmptyConfig, RuntimeMap>(
      pluginId: PluginId('aitum'),
      actionId: ActionId('saveBacktrack'),
      displayName: 'Save Backtrack',
      configCodec: aitumEmptyConfigCodec,
      invoke: (config, context) => _call(transport, 'save_backtrack', {}),
    ),
    ActionSpec<AitumChapterConfig, RuntimeMap>(
      pluginId: PluginId('aitum'),
      actionId: ActionId('verticalChapterMarker'),
      displayName: 'Vertical Chapter Marker',
      configSchema: _chapterSchema,
      configCodec: aitumChapterConfigCodec,
      invoke: (config, context) =>
          _call(transport, 'add_chapter', {'chapter_name': config.chapterName}),
    ),
  ],
);

Future<RuntimeMap> _toggle(
  ObsTransport transport,
  AitumToggleMode mode,
  String stateKey,
) async {
  if (mode == AitumToggleMode.toggle) {
    final status = await _call(transport, 'status', {});
    final responseData = status['responseData'];
    final current = responseData is Map && responseData[stateKey] == true;
    return _call(transport, current ? 'stop_$stateKey' : 'start_$stateKey', {});
  }
  return _call(
    transport,
    mode == AitumToggleMode.disabled ? 'stop_$stateKey' : 'start_$stateKey',
    {},
  );
}

Future<RuntimeMap> _call(
  ObsTransport transport,
  String requestType,
  RuntimeMap requestData,
) => transport.call('CallVendorRequest', {
  'vendorName': _vendorName,
  'requestType': requestType,
  if (requestData.isNotEmpty) 'requestData': requestData,
});
