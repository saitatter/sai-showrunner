import '../../schema/data_input.dart';
import '../../persistence/viewer_data_repository.dart';
import '../../runtime/expression.dart';
import '../../services/plugin_event_hub.dart';
import '../registry/plugin_contract.dart';
import 'contracts.dart';
import 'runtime.dart';

const _variableSchema = DartDataInputSchema(
  label: 'Variable',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Variable',
      key: 'variable',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Value',
      key: 'value',
      kind: DartDataInputKind.multilineText,
    ),
  ],
);

const _viewerVariableSchema = DartDataInputSchema(
  label: 'Viewer variable',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Viewer',
      key: 'viewer',
      kind: DartDataInputKind.object,
      required: true,
      fields: [
        DartDataInputSchema(
          label: 'ID',
          key: 'id',
          kind: DartDataInputKind.text,
          required: true,
        ),
        DartDataInputSchema(
          label: 'Display name',
          key: 'displayName',
          kind: DartDataInputKind.text,
        ),
      ],
    ),
    DartDataInputSchema(
      label: 'Variable',
      key: 'variable',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Value',
      key: 'value',
      kind: DartDataInputKind.multilineText,
    ),
  ],
);

const _viewerOffsetSchema = DartDataInputSchema(
  label: 'Viewer variable offset',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Viewer',
      key: 'viewer',
      kind: DartDataInputKind.object,
      required: true,
      fields: [
        DartDataInputSchema(
          label: 'ID',
          key: 'id',
          kind: DartDataInputKind.text,
          required: true,
        ),
        DartDataInputSchema(
          label: 'Display name',
          key: 'displayName',
          kind: DartDataInputKind.text,
        ),
      ],
    ),
    DartDataInputSchema(
      label: 'Variable',
      key: 'variable',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Offset',
      key: 'offset',
      kind: DartDataInputKind.number,
      required: true,
    ),
  ],
);

const _offsetVariableSchema = DartDataInputSchema(
  label: 'Variable offset',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Variable',
      key: 'variable',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Offset',
      key: 'offset',
      kind: DartDataInputKind.number,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Clamp',
      key: 'clamp',
      kind: DartDataInputKind.object,
      fields: [
        DartDataInputSchema(
          label: 'Minimum',
          key: 'min',
          kind: DartDataInputKind.number,
        ),
        DartDataInputSchema(
          label: 'Maximum',
          key: 'max',
          kind: DartDataInputKind.number,
        ),
      ],
    ),
  ],
);

DartPluginManifest createVariablesPlugin({
  ViewerDataRepository? viewerDataRepository,
  DartPluginEventHub? eventHub,
  DartVariableRuntime? variableRuntime,
}) {
  final repository = viewerDataRepository ?? InMemoryViewerDataRepository();
  return DartPluginManifest(
    id: PluginId('variables'),
    name: 'Variables',
    actions: [
      ActionSpec<VariableValueConfig, RuntimeMap>(
        pluginId: PluginId('variables'),
        actionId: ActionId('set'),
        displayName: 'Set Variable',
        configSchema: _variableSchema,
        configCodec: variableValueConfigCodec,
        invoke: (config, context) =>
            _setVariable(config, context, variableRuntime),
      ),
      ActionSpec<VariableOffsetConfig, RuntimeMap>(
        pluginId: PluginId('variables'),
        actionId: ActionId('offset'),
        displayName: 'Offset Variable',
        configSchema: _offsetVariableSchema,
        configCodec: variableOffsetConfigCodec,
        invoke: (config, context) =>
            _offsetVariable(config, context, variableRuntime),
      ),
      ActionSpec<VariableValueConfig, RuntimeMap>(
        pluginId: PluginId('variables'),
        actionId: ActionId('setVariable'),
        displayName: 'Set Variable',
        configSchema: _variableSchema,
        configCodec: variableValueConfigCodec,
        invoke: (config, context) =>
            _setVariable(config, context, variableRuntime),
      ),
      ActionSpec<VariableNameConfig, RuntimeMap>(
        pluginId: PluginId('variables'),
        actionId: ActionId('getVariable'),
        displayName: 'Get Variable',
        configSchema: const DartDataInputSchema(
          label: 'Variable',
          kind: DartDataInputKind.object,
          fields: [
            DartDataInputSchema(
              label: 'Variable',
              key: 'variable',
              kind: DartDataInputKind.text,
              required: true,
            ),
          ],
        ),
        configCodec: variableNameConfigCodec,
        invoke: (config, context) =>
            _getVariable(config, context, variableRuntime),
      ),
      ActionSpec<ViewerVariableValueConfig, RuntimeMap>(
        pluginId: PluginId('variables'),
        actionId: ActionId('setViewerVar'),
        displayName: 'Set Viewer Variable',
        configSchema: _viewerVariableSchema,
        configCodec: viewerVariableValueConfigCodec,
        invoke: (config, context) =>
            _setViewerVar(config, context, repository, eventHub),
      ),
      ActionSpec<ViewerVariableOffsetConfig, RuntimeMap>(
        pluginId: PluginId('variables'),
        actionId: ActionId('offsetViewerVar'),
        displayName: 'Offset Viewer Variable',
        configSchema: _viewerOffsetSchema,
        configCodec: viewerVariableOffsetConfigCodec,
        invoke: (config, context) =>
            _offsetViewerVar(config, context, repository, eventHub),
      ),
    ],
  );
}

Future<RuntimeMap> _setVariable(
  VariableValueConfig config,
  EvaluationContext context,
  DartVariableRuntime? variableRuntime,
) async {
  final variable = config.variable;
  final value = config.value;
  if (variableRuntime != null) {
    await variableRuntime.reload();
    final definition = variableRuntime.definitionOf(variable);
    if (definition == null) {
      return {'variable': variable, 'value': null, 'updated': false};
    }
    final updated = await variableRuntime.setValue(variable, value);
    _setContextVariable(context, definition.id, updated);
    return {'variable': definition.id, 'value': updated, 'updated': true};
  }
  if (variable.isNotEmpty) {
    _setContextVariable(context, variable, value);
  }
  return {'variable': variable, 'value': value};
}

Future<RuntimeMap> _getVariable(
  VariableNameConfig config,
  EvaluationContext context,
  DartVariableRuntime? variableRuntime,
) async {
  final variable = config.variable;
  if (variableRuntime != null) {
    await variableRuntime.reload();
    final definition = variableRuntime.definitionOf(variable);
    if (definition == null) return {'variable': variable, 'value': null};
    final value = definition.currentValue;
    _setContextVariable(context, definition.id, value);
    return {'variable': definition.id, 'value': value};
  }
  final value = _contextVariable(context, variable);
  return {'variable': variable, 'value': value};
}

Future<RuntimeMap> _offsetVariable(
  VariableOffsetConfig config,
  EvaluationContext context,
  DartVariableRuntime? variableRuntime,
) async {
  final variable = config.variable;
  if (variableRuntime != null) {
    await variableRuntime.reload();
    final definition = variableRuntime.definitionOf(variable);
    final offset = config.offset;
    if (definition == null || offset is! num) {
      return {
        'variable': variable,
        'value': definition?.currentValue,
        'updated': false,
      };
    }
    final updated = await variableRuntime.offsetValue(
      definition.id,
      offset,
      minimum: config.minimum,
      maximum: config.maximum,
    );
    _setContextVariable(context, definition.id, updated);
    return {'variable': definition.id, 'value': updated, 'updated': true};
  }
  final current = _contextVariable(context, variable);
  final offset = config.offset;
  if (variable.isEmpty || current is! num || offset is! num) {
    return {'variable': variable, 'value': current};
  }
  var value = current + offset;
  final minimum = config.minimum;
  final maximum = config.maximum;
  if (minimum != null && value < minimum) value = minimum;
  if (maximum != null && value > maximum) value = maximum;
  _setContextVariable(context, variable, value);
  return {'variable': variable, 'value': value};
}

dynamic _contextVariable(EvaluationContext context, String variable) {
  if (context.contextState.containsKey(variable)) {
    return context.contextState[variable];
  }
  final variables = context.contextState['variables'];
  if (variables is Map && variables.containsKey(variable)) {
    return variables[variable];
  }
  return context.locals[variable];
}

void _setContextVariable(
  EvaluationContext context,
  String variable,
  dynamic value,
) {
  context.contextState[variable] = value;
  final state = context.contextState['variables'];
  if (state is Map) {
    state[variable] = value;
  } else {
    context.contextState['variables'] = {variable: value};
  }
}

Future<RuntimeMap> _setViewerVar(
  ViewerVariableValueConfig config,
  EvaluationContext _,
  ViewerDataRepository repository,
  DartPluginEventHub? eventHub,
) async {
  final variable = _requiredConfigString(config.variable, 'variable');
  final viewer = config.viewer;
  final row = await repository.setViewerValue(
    'twitch',
    viewer,
    variable,
    config.value,
  );
  eventHub?.emit('viewerDataChanged', {
    'provider': row.provider,
    'id': row.viewer.id,
    'displayName': row.viewer.displayName,
    'variable': variable,
    'value': row.values[variable],
    'values': row.values,
  });
  return {
    'provider': row.provider,
    'viewer': row.viewer.id,
    'variable': variable,
    'value': row.values[variable],
  };
}

Future<RuntimeMap> _offsetViewerVar(
  ViewerVariableOffsetConfig config,
  EvaluationContext _,
  ViewerDataRepository repository,
  DartPluginEventHub? eventHub,
) async {
  final variable = _requiredConfigString(config.variable, 'variable');
  final rawOffset = config.offset;
  if (rawOffset == null) {
    throw ArgumentError.value(
      rawOffset,
      'offset',
      'Viewer variable offsets must be numbers.',
    );
  }
  final viewer = config.viewer;
  final row = await repository.offsetViewerValue(
    'twitch',
    viewer,
    variable,
    rawOffset,
  );
  eventHub?.emit('viewerDataChanged', {
    'provider': row.provider,
    'id': row.viewer.id,
    'displayName': row.viewer.displayName,
    'variable': variable,
    'value': row.values[variable],
    'values': row.values,
  });
  return {
    'provider': row.provider,
    'viewer': row.viewer.id,
    'variable': variable,
    'value': row.values[variable],
  };
}

String _requiredConfigString(String rawValue, String key) {
  final value = rawValue.trim();
  if (value.isEmpty) throw ArgumentError.value(rawValue, key);
  return value;
}
