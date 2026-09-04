import '../../runtime/expression.dart';
import '../../components/data_inputs/data_input.dart';
import '../registry/plugin_registry.dart';

const _lightColorField = DartDataInputSchema(
  label: 'Color',
  key: 'lightColor',
  kind: DartDataInputKind.lightColor,
);

const _setLightColorSchema = DartDataInputSchema(
  label: 'Set light color',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Light',
      key: 'lightId',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Color',
      key: 'color',
      kind: DartDataInputKind.lightColor,
    ),
  ],
);

const _toggleLightSchema = DartDataInputSchema(
  label: 'Toggle light',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Light',
      key: 'lightId',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'State',
      key: 'state',
      kind: DartDataInputKind.enumeration,
      options: ['true', 'false', 'toggle'],
      defaultValue: 'toggle',
    ),
  ],
);

const _lightSchema = DartDataInputSchema(
  label: 'Change light',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Light',
      key: 'light',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'On',
      key: 'on',
      kind: DartDataInputKind.enumeration,
      options: ['true', 'false', 'toggle'],
      defaultValue: 'true',
    ),
    _lightColorField,
    DartDataInputSchema(
      label: 'Transition time (seconds)',
      key: 'transition',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 0.5,
    ),
  ],
);

DartPluginManifest createIotPlugin() => const DartPluginManifest(
  id: 'iot',
  name: 'IoT & Smart Home',
  actions: [
    DartActionDefinition(
      pluginId: 'iot',
      actionId: 'setLightColor',
      displayName: 'Set Light Color',
      configSchema: _setLightColorSchema,
      invoke: _setLightColor,
    ),
    DartActionDefinition(
      pluginId: 'iot',
      actionId: 'toggleLight',
      displayName: 'Toggle Light',
      configSchema: _toggleLightSchema,
      invoke: _toggleLight,
    ),
    DartActionDefinition(
      pluginId: 'iot',
      actionId: 'light',
      displayName: 'Change Light',
      configSchema: _lightSchema,
      invoke: _light,
    ),
    DartActionDefinition(
      pluginId: 'iot',
      actionId: 'plug',
      displayName: 'Switch Plug',
      invoke: _plug,
    ),
  ],
);

Future<Object?> _setLightColor(
  RuntimeMap config,
  EvaluationContext context,
) async {
  final lightId = config['lightId']?.toString() ?? '';
  final color = config['color']?.toString() ?? '#ffffff';
  return {'updated': lightId.isNotEmpty, 'lightId': lightId, 'color': color};
}

Future<Object?> _toggleLight(
  RuntimeMap config,
  EvaluationContext context,
) async {
  final lightId = config['lightId']?.toString() ?? '';
  final state = config['state'] ?? true;
  return {'toggled': lightId.isNotEmpty, 'lightId': lightId, 'state': state};
}

Future<Object?> _light(RuntimeMap config, EvaluationContext context) async => {
  'lightOn': config['on'] ?? true,
  'lightId': config['light'] ?? config['lightId'],
  'color': config['lightColor'] ?? config['color'],
};

Future<Object?> _plug(RuntimeMap config, EvaluationContext context) async => {
  'plugOn': config['switch'] ?? config['on'] ?? true,
  'plugId': config['plug'] ?? config['plugId'],
};
