import 'dart:convert';

import '../../schema/data_input.dart';
import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

const _numberValue = DartDataInputSchema(
  label: 'Number',
  kind: DartDataInputKind.number,
  key: 'value',
  required: true,
);
const _booleanValue = DartDataInputSchema(
  label: 'Boolean',
  kind: DartDataInputKind.boolean,
  key: 'value',
  required: true,
);
const _textValue = DartDataInputSchema(
  label: 'Text',
  kind: DartDataInputKind.text,
  key: 'value',
  required: true,
);
const _jsonValue = DartDataInputSchema(
  label: 'JSON',
  kind: DartDataInputKind.multilineText,
  key: 'value',
  required: true,
  multiline: true,
);
const _fallbackNumber = DartDataInputSchema(
  label: 'Fallback',
  kind: DartDataInputKind.number,
  key: 'fallback',
);
const _fallbackBoolean = DartDataInputSchema(
  label: 'Fallback',
  kind: DartDataInputKind.boolean,
  key: 'fallback',
);
const _stringResult = DartDataInputSchema(
  label: 'Returns',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Value',
      key: 'value',
      kind: DartDataInputKind.text,
    ),
  ],
);
const _numberResult = DartDataInputSchema(
  label: 'Returns',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Value',
      key: 'value',
      kind: DartDataInputKind.number,
    ),
  ],
);
const _booleanResult = DartDataInputSchema(
  label: 'Returns',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Value',
      key: 'value',
      kind: DartDataInputKind.boolean,
    ),
  ],
);
const _numberConversionResult = DartDataInputSchema(
  label: 'Returns',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Value',
      key: 'value',
      kind: DartDataInputKind.number,
    ),
    DartDataInputSchema(
      label: 'Converted',
      key: 'converted',
      kind: DartDataInputKind.boolean,
    ),
  ],
);
const _booleanConversionResult = DartDataInputSchema(
  label: 'Returns',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Value',
      key: 'value',
      kind: DartDataInputKind.boolean,
    ),
    DartDataInputSchema(
      label: 'Converted',
      key: 'converted',
      kind: DartDataInputKind.boolean,
    ),
  ],
);
const _objectConversionResult = DartDataInputSchema(
  label: 'Returns',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Value',
      key: 'value',
      kind: DartDataInputKind.object,
    ),
    DartDataInputSchema(
      label: 'Converted',
      key: 'converted',
      kind: DartDataInputKind.boolean,
    ),
  ],
);
const _arrayConversionResult = DartDataInputSchema(
  label: 'Returns',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Value',
      key: 'value',
      kind: DartDataInputKind.array,
    ),
    DartDataInputSchema(
      label: 'Converted',
      key: 'converted',
      kind: DartDataInputKind.boolean,
    ),
  ],
);

DartPluginManifest createShowRunnerPlugin() => const DartPluginManifest(
  id: 'ShowRunner',
  name: 'ShowRunner',
  settings: [
    DartSettingDefinition(
      id: 'port',
      displayName: 'Internal Webserver Port',
      defaultValue: 8181,
    ),
  ],
  actions: [
    DartActionDefinition(
      pluginId: 'ShowRunner',
      actionId: 'convertNumberToString',
      displayName: 'Convert Number To String',
      invoke: _convertNumberToString,
      resultSchema: _stringResult,
      configSchema: DartDataInputSchema(
        label: '',
        kind: DartDataInputKind.object,
        fields: [_numberValue],
      ),
    ),
    DartActionDefinition(
      pluginId: 'ShowRunner',
      actionId: 'convertBooleanToString',
      displayName: 'Convert Boolean To String',
      invoke: _convertBooleanToString,
      resultSchema: _stringResult,
      configSchema: DartDataInputSchema(
        label: '',
        kind: DartDataInputKind.object,
        fields: [_booleanValue],
      ),
    ),
    DartActionDefinition(
      pluginId: 'ShowRunner',
      actionId: 'convertStringToNumber',
      displayName: 'Convert String To Number',
      invoke: _convertStringToNumber,
      resultSchema: _numberConversionResult,
      configSchema: DartDataInputSchema(
        label: '',
        kind: DartDataInputKind.object,
        fields: [_textValue, _fallbackNumber],
      ),
    ),
    DartActionDefinition(
      pluginId: 'ShowRunner',
      actionId: 'convertBooleanToNumber',
      displayName: 'Convert Boolean To Number',
      invoke: _convertBooleanToNumber,
      resultSchema: _numberResult,
      configSchema: DartDataInputSchema(
        label: '',
        kind: DartDataInputKind.object,
        fields: [_booleanValue],
      ),
    ),
    DartActionDefinition(
      pluginId: 'ShowRunner',
      actionId: 'convertNumberToBoolean',
      displayName: 'Convert Number To Boolean',
      invoke: _convertNumberToBoolean,
      resultSchema: _booleanResult,
      configSchema: DartDataInputSchema(
        label: '',
        kind: DartDataInputKind.object,
        fields: [_numberValue],
      ),
    ),
    DartActionDefinition(
      pluginId: 'ShowRunner',
      actionId: 'convertStringToBoolean',
      displayName: 'Convert String To Boolean',
      invoke: _convertStringToBoolean,
      resultSchema: _booleanConversionResult,
      configSchema: DartDataInputSchema(
        label: '',
        kind: DartDataInputKind.object,
        fields: [_textValue, _fallbackBoolean],
      ),
    ),
    DartActionDefinition(
      pluginId: 'ShowRunner',
      actionId: 'convertObjectToJsonString',
      displayName: 'Convert Object To JSON String',
      invoke: _convertObjectToJsonString,
      resultSchema: _stringResult,
      configSchema: DartDataInputSchema(
        label: '',
        kind: DartDataInputKind.object,
        fields: [
          DartDataInputSchema(
            label: 'Object',
            kind: DartDataInputKind.object,
            key: 'value',
            required: true,
          ),
        ],
      ),
    ),
    DartActionDefinition(
      pluginId: 'ShowRunner',
      actionId: 'convertArrayToJsonString',
      displayName: 'Convert Array To JSON String',
      invoke: _convertArrayToJsonString,
      resultSchema: _stringResult,
      configSchema: DartDataInputSchema(
        label: '',
        kind: DartDataInputKind.object,
        fields: [
          DartDataInputSchema(
            label: 'Array',
            kind: DartDataInputKind.array,
            key: 'value',
            required: true,
          ),
        ],
      ),
    ),
    DartActionDefinition(
      pluginId: 'ShowRunner',
      actionId: 'convertJsonStringToObject',
      displayName: 'Convert JSON String To Object',
      invoke: _convertJsonStringToObject,
      resultSchema: _objectConversionResult,
      configSchema: DartDataInputSchema(
        label: '',
        kind: DartDataInputKind.object,
        fields: [_jsonValue],
      ),
    ),
    DartActionDefinition(
      pluginId: 'ShowRunner',
      actionId: 'convertJsonStringToArray',
      displayName: 'Convert JSON String To Array',
      invoke: _convertJsonStringToArray,
      resultSchema: _arrayConversionResult,
      configSchema: DartDataInputSchema(
        label: '',
        kind: DartDataInputKind.object,
        fields: [_jsonValue],
      ),
    ),
  ],
);

Future<Object?> _convertNumberToString(
  RuntimeMap config,
  EvaluationContext context,
) async => {'value': '${config['value'] ?? 0}'};

Future<Object?> _convertBooleanToString(
  RuntimeMap config,
  EvaluationContext context,
) async => {'value': config['value'] == true ? 'true' : 'false'};

Future<Object?> _convertStringToNumber(
  RuntimeMap config,
  EvaluationContext context,
) async {
  final text = '${config['value'] ?? ''}'.trim();
  final fallback = _number(config['fallback']);
  if (text.isEmpty) return {'value': fallback, 'converted': false};
  final parsed = num.tryParse(text);
  final converted = parsed != null && parsed.isFinite;
  return {'value': converted ? parsed : fallback, 'converted': converted};
}

Future<Object?> _convertBooleanToNumber(
  RuntimeMap config,
  EvaluationContext context,
) async => {'value': config['value'] == true ? 1 : 0};

Future<Object?> _convertNumberToBoolean(
  RuntimeMap config,
  EvaluationContext context,
) async {
  final value = config['value'];
  return {'value': value is num && value.isFinite && value != 0};
}

Future<Object?> _convertStringToBoolean(
  RuntimeMap config,
  EvaluationContext context,
) async {
  final parsed = _parseBooleanText(config['value']);
  return {
    'value': parsed ?? config['fallback'] == true,
    'converted': parsed != null,
  };
}

Future<Object?> _convertObjectToJsonString(
  RuntimeMap config,
  EvaluationContext context,
) async => {
  'value': _safeJsonStringify(config['value'] ?? <String, dynamic>{}),
};

Future<Object?> _convertArrayToJsonString(
  RuntimeMap config,
  EvaluationContext context,
) async => {
  'value': _safeJsonStringify(
    config['value'] is List ? config['value'] : const [],
  ),
};

Future<Object?> _convertJsonStringToObject(
  RuntimeMap config,
  EvaluationContext context,
) async {
  final parsed = _safeJsonParse(config['value']);
  final converted = parsed is Map;
  return {
    'value': converted
        ? Map<String, dynamic>.from(parsed)
        : <String, dynamic>{},
    'converted': converted,
  };
}

Future<Object?> _convertJsonStringToArray(
  RuntimeMap config,
  EvaluationContext context,
) async {
  final parsed = _safeJsonParse(config['value']);
  final converted = parsed is List;
  return {'value': converted ? parsed : <dynamic>[], 'converted': converted};
}

bool? _parseBooleanText(dynamic value) {
  final normalized = '${value ?? ''}'.trim().toLowerCase();
  if (const {'true', '1', 'yes', 'y', 'on'}.contains(normalized)) return true;
  if (const {'false', '0', 'no', 'n', 'off'}.contains(normalized)) return false;
  return null;
}

num _number(dynamic value) =>
    value is num ? value : num.tryParse('$value') ?? 0;

String _safeJsonStringify(dynamic value) {
  try {
    return jsonEncode(value);
  } on Object {
    return 'null';
  }
}

dynamic _safeJsonParse(dynamic value) {
  try {
    return jsonDecode('${value ?? ''}');
  } on FormatException {
    return null;
  }
}
