import '../../components/data_inputs/data_input.dart';
import '../../runtime/expression.dart';
import '../obs/actions.dart';
import '../registry/plugin_registry.dart';

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

DartPluginManifest createAitumPlugin(ObsTransport transport) =>
    DartPluginManifest(
      id: 'aitum',
      name: 'Aitum',
      settings: const [
        DartSettingDefinition(
          id: 'obsConnection',
          displayName: 'OBS Connection',
        ),
      ],
      actions: [
        DartActionDefinition(
          pluginId: 'aitum',
          actionId: 'verticalScene',
          displayName: 'Change Vertical Scene',
          configSchema: _sceneSchema,
          invoke: (config, context) => _call(transport, 'switch_scene', {
            'scene': config['scene']?.toString() ?? '',
          }),
        ),
        DartActionDefinition(
          pluginId: 'aitum',
          actionId: 'verticalStreamStartStop',
          displayName: 'Vertical Stream Start/Stop',
          configSchema: _toggleSchema,
          invoke: (config, context) =>
              _toggle(transport, config['streaming'], 'streaming'),
        ),
        DartActionDefinition(
          pluginId: 'aitum',
          actionId: 'verticalRecordingStartStop',
          displayName: 'Vertical Recording Start/Stop',
          configSchema: _toggleSchema,
          invoke: (config, context) =>
              _toggle(transport, config['streaming'], 'recording'),
        ),
        DartActionDefinition(
          pluginId: 'aitum',
          actionId: 'verticalBacktrackStartStop',
          displayName: 'Vertical Backtrack Start/Stop',
          configSchema: _toggleSchema,
          invoke: (config, context) =>
              _toggle(transport, config['streaming'], 'backtrack'),
        ),
        DartActionDefinition(
          pluginId: 'aitum',
          actionId: 'saveBacktrack',
          displayName: 'Save Backtrack',
          invoke: (config, context) => _call(transport, 'save_backtrack', {}),
        ),
        DartActionDefinition(
          pluginId: 'aitum',
          actionId: 'verticalChapterMarker',
          displayName: 'Vertical Chapter Marker',
          configSchema: _chapterSchema,
          invoke: (config, context) => _call(transport, 'add_chapter', {
            'chapter_name': config['chapterName']?.toString() ?? '',
          }),
        ),
      ],
    );

Future<Object?> _toggle(
  ObsTransport transport,
  Object? value,
  String stateKey,
) async {
  final state = value?.toString() ?? 'true';
  if (state == 'toggle') {
    final status = await _call(transport, 'status', {});
    final responseData = status['responseData'];
    final current = responseData is Map && responseData[stateKey] == true;
    return _call(transport, current ? 'stop_$stateKey' : 'start_$stateKey', {});
  }
  return _call(
    transport,
    state == 'false' || value == false ? 'stop_$stateKey' : 'start_$stateKey',
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
