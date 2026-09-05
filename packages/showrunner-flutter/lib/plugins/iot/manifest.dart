import '../../runtime/expression.dart';
import '../../components/data_inputs/data_input.dart';
import '../registry/plugin_registry.dart';

typedef IotResourceActionResolver =
    Future<Object?> Function(
      String resourceType,
      String resourceId,
      RuntimeMap config,
      EvaluationContext context,
    );

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

const _plugSchema = DartDataInputSchema(
  label: 'Change plug',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Plug',
      key: 'plug',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'State',
      key: 'switch',
      kind: DartDataInputKind.enumeration,
      options: ['true', 'false', 'toggle'],
      defaultValue: 'true',
    ),
  ],
);

DartPluginManifest createIotPlugin({IotResourceActionResolver? resolver}) =>
    DartPluginManifest(
      id: 'iot',
      name: 'IoT & Smart Home',
      actions: [
        DartActionDefinition(
          pluginId: 'iot',
          actionId: 'setLightColor',
          displayName: 'Set Light Color',
          configSchema: _setLightColorSchema,
          invoke: (config, context) =>
              _setLightColor(resolver, config, context),
        ),
        DartActionDefinition(
          pluginId: 'iot',
          actionId: 'toggleLight',
          displayName: 'Toggle Light',
          configSchema: _toggleLightSchema,
          invoke: (config, context) => _toggleLight(resolver, config, context),
        ),
        DartActionDefinition(
          pluginId: 'iot',
          actionId: 'light',
          displayName: 'Change Light',
          configSchema: _lightSchema,
          invoke: (config, context) => _light(resolver, config, context),
        ),
        DartActionDefinition(
          pluginId: 'iot',
          actionId: 'plug',
          displayName: 'Switch Plug',
          configSchema: _plugSchema,
          invoke: (config, context) => _plug(resolver, config, context),
        ),
      ],
    );

Future<Object?> _setLightColor(
  IotResourceActionResolver? resolver,
  RuntimeMap config,
  EvaluationContext context,
) async {
  final lightId = _resourceId(config['lightId']);
  final color = config['color']?.toString() ?? '#ffffff';
  if (lightId.isEmpty) throw ArgumentError('lightId is required.');
  return _resolve(resolver, 'Light', lightId, {
    ...config,
    'lightId': lightId,
    'color': color,
  }, context);
}

Future<Object?> _toggleLight(
  IotResourceActionResolver? resolver,
  RuntimeMap config,
  EvaluationContext context,
) async {
  final lightId = _resourceId(config['lightId']);
  final state = config['state'] ?? true;
  if (lightId.isEmpty) throw ArgumentError('lightId is required.');
  return _resolve(resolver, 'Light', lightId, {
    ...config,
    'lightId': lightId,
    'state': state,
  }, context);
}

Future<Object?> _light(
  IotResourceActionResolver? resolver,
  RuntimeMap config,
  EvaluationContext context,
) async {
  final lightId = _resourceId(config['light'] ?? config['lightId']);
  if (lightId.isEmpty) throw ArgumentError('light is required.');
  return _resolve(resolver, 'Light', lightId, {
    ...config,
    'lightId': lightId,
    'on': config['on'] ?? true,
    'color': config['lightColor'] ?? config['color'],
  }, context);
}

Future<Object?> _plug(
  IotResourceActionResolver? resolver,
  RuntimeMap config,
  EvaluationContext context,
) async {
  final plugId = _resourceId(config['plug'] ?? config['plugId']);
  if (plugId.isEmpty) throw ArgumentError('plug is required.');
  return _resolve(resolver, 'Plug', plugId, {
    ...config,
    'plugId': plugId,
    'on': config['switch'] ?? config['on'] ?? true,
  }, context);
}

Future<Object?> _resolve(
  IotResourceActionResolver? resolver,
  String resourceType,
  String resourceId,
  RuntimeMap config,
  EvaluationContext context,
) {
  if (resolver == null) {
    throw StateError(
      'IoT $resourceType resources require a configured device resolver.',
    );
  }
  return resolver(resourceType, resourceId, config, context);
}

String _resourceId(Object? value) {
  if (value is Map) {
    return value['id']?.toString().trim() ?? '';
  }
  return value?.toString().trim() ?? '';
}
