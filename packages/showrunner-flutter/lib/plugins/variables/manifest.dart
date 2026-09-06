import '../../schema/data_input.dart';
import '../../persistence/viewer_data_repository.dart';
import '../../runtime/expression.dart';
import '../../schema/viewer_data.dart';
import '../../services/plugin_event_hub.dart';
import '../registry/plugin_contract.dart';
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
    id: 'variables',
    name: 'Variables',
    start: variableRuntime?.load,
    actions: [
      DartActionDefinition(
        pluginId: 'variables',
        actionId: 'set',
        displayName: 'Set Variable',
        configSchema: _variableSchema,
        invoke: (config, context) =>
            _setVariable(config, context, variableRuntime),
      ),
      DartActionDefinition(
        pluginId: 'variables',
        actionId: 'offset',
        displayName: 'Offset Variable',
        configSchema: _offsetVariableSchema,
        invoke: (config, context) =>
            _offsetVariable(config, context, variableRuntime),
      ),
      DartActionDefinition(
        pluginId: 'variables',
        actionId: 'setVariable',
        displayName: 'Set Variable',
        configSchema: _variableSchema,
        invoke: (config, context) =>
            _setVariable(config, context, variableRuntime),
      ),
      DartActionDefinition(
        pluginId: 'variables',
        actionId: 'getVariable',
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
        invoke: (config, context) =>
            _getVariable(config, context, variableRuntime),
      ),
      DartActionDefinition(
        pluginId: 'variables',
        actionId: 'setViewerVar',
        displayName: 'Set Viewer Variable',
        configSchema: _viewerVariableSchema,
        invoke: (config, context) =>
            _setViewerVar(config, context, repository, eventHub),
      ),
      DartActionDefinition(
        pluginId: 'variables',
        actionId: 'offsetViewerVar',
        displayName: 'Offset Viewer Variable',
        configSchema: _viewerOffsetSchema,
        invoke: (config, context) =>
            _offsetViewerVar(config, context, repository, eventHub),
      ),
    ],
  );
}

Future<Object?> _setVariable(
  RuntimeMap config,
  EvaluationContext context,
  DartVariableRuntime? variableRuntime,
) async {
  final variable = config['variable']?.toString() ?? '';
  final value = config['value'];
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

Future<Object?> _getVariable(
  RuntimeMap config,
  EvaluationContext context,
  DartVariableRuntime? variableRuntime,
) async {
  final variable = config['variable']?.toString() ?? '';
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

Future<Object?> _offsetVariable(
  RuntimeMap config,
  EvaluationContext context,
  DartVariableRuntime? variableRuntime,
) async {
  final variable = config['variable']?.toString() ?? '';
  if (variableRuntime != null) {
    await variableRuntime.reload();
    final definition = variableRuntime.definitionOf(variable);
    final offset = config['offset'];
    if (definition == null || offset is! num) {
      return {
        'variable': variable,
        'value': definition?.currentValue,
        'updated': false,
      };
    }
    final clamp = config['clamp'];
    final updated = await variableRuntime.offsetValue(
      definition.id,
      offset,
      minimum: clamp is Map && clamp['min'] is num ? clamp['min'] as num : null,
      maximum: clamp is Map && clamp['max'] is num ? clamp['max'] as num : null,
    );
    _setContextVariable(context, definition.id, updated);
    return {'variable': definition.id, 'value': updated, 'updated': true};
  }
  final current = _contextVariable(context, variable);
  final offset = config['offset'];
  if (variable.isEmpty || current is! num || offset is! num) {
    return {'variable': variable, 'value': current};
  }
  var value = current + offset;
  final clamp = config['clamp'];
  if (clamp is Map) {
    final minimum = clamp['min'];
    final maximum = clamp['max'];
    if (minimum is num && value < minimum) value = minimum;
    if (maximum is num && value > maximum) value = maximum;
  }
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

Future<Object?> _setViewerVar(
  RuntimeMap config,
  EvaluationContext _,
  ViewerDataRepository repository,
  DartPluginEventHub? eventHub,
) async {
  final variable = _requiredConfigString(config, 'variable');
  final viewer = ViewerIdentity.fromConfig(config['viewer']);
  final row = await repository.setViewerValue(
    'twitch',
    viewer,
    variable,
    config['value'],
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

Future<Object?> _offsetViewerVar(
  RuntimeMap config,
  EvaluationContext _,
  ViewerDataRepository repository,
  DartPluginEventHub? eventHub,
) async {
  final variable = _requiredConfigString(config, 'variable');
  final rawOffset = config['offset'];
  if (rawOffset is! num) {
    throw ArgumentError.value(
      rawOffset,
      'offset',
      'Viewer variable offsets must be numbers.',
    );
  }
  final viewer = ViewerIdentity.fromConfig(config['viewer']);
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

String _requiredConfigString(RuntimeMap config, String key) {
  final value = config[key]?.toString().trim() ?? '';
  if (value.isEmpty) throw ArgumentError.value(config[key], key);
  return value;
}
