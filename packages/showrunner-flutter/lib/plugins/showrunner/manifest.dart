import 'dart:convert';

import '../../schema/data_input.dart';
import '../../schema/automation.dart';
import '../../runtime/automation_queue_manager.dart';
import '../../runtime/action_queue.dart';
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

const _queueReference = DartDataInputSchema(
  label: 'Queue',
  kind: DartDataInputKind.resource,
  key: 'queue',
  required: true,
  resourceType: 'ActionQueue',
);
const _optionalQueueReference = DartDataInputSchema(
  label: 'Queue',
  kind: DartDataInputKind.resource,
  key: 'queue',
  resourceType: 'ActionQueue',
);
const _automationReference = DartDataInputSchema(
  label: 'Worker Automation',
  kind: DartDataInputKind.resource,
  key: 'automation',
  required: true,
  resourceType: 'Automation',
);
const _addToQueueSchema = DartDataInputSchema(
  label: '',
  kind: DartDataInputKind.object,
  fields: [
    _queueReference,
    _automationReference,
    DartDataInputSchema(
      label: 'Payload',
      kind: DartDataInputKind.object,
      key: 'payload',
    ),
  ],
);
const _queueControlSchema = DartDataInputSchema(
  label: '',
  kind: DartDataInputKind.object,
  fields: [_queueReference],
);
const _pauseQueueSchema = DartDataInputSchema(
  label: '',
  kind: DartDataInputKind.object,
  fields: [
    _queueReference,
    DartDataInputSchema(
      label: 'Paused',
      kind: DartDataInputKind.enumeration,
      key: 'paused',
      options: ['true', 'false', 'toggle'],
      required: true,
      defaultValue: 'toggle',
    ),
  ],
);
const _queueTriggerSchema = DartDataInputSchema(
  label: '',
  kind: DartDataInputKind.object,
  fields: [_optionalQueueReference],
);
const _autoRunSchema = DartDataInputSchema(
  label: '',
  kind: DartDataInputKind.object,
);
const _conditionTriggerSchema = DartDataInputSchema(
  label: '',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Condition',
      key: 'condition',
      kind: DartDataInputKind.object,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Run on enable',
      key: 'runImmediately',
      kind: DartDataInputKind.boolean,
      defaultValue: false,
    ),
  ],
);
const _queueResultSchema = DartDataInputSchema(
  label: 'Returns',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Queued',
      key: 'queued',
      kind: DartDataInputKind.boolean,
    ),
    DartDataInputSchema(
      label: 'Queue ID',
      key: 'queueId',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      label: 'Automation ID',
      key: 'automationId',
      kind: DartDataInputKind.text,
    ),
  ],
);
const _completedQueueResultSchema = DartDataInputSchema(
  label: 'Returns',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Completed',
      key: 'completed',
      kind: DartDataInputKind.boolean,
    ),
  ],
);
const _profileReference = DartDataInputSchema(
  label: 'Profile',
  kind: DartDataInputKind.resource,
  key: 'profile',
  required: true,
  resourceType: 'Profile',
);
const _profileActivationSchema = DartDataInputSchema(
  label: '',
  kind: DartDataInputKind.object,
  fields: [
    _profileReference,
    DartDataInputSchema(
      label: 'Activation',
      kind: DartDataInputKind.enumeration,
      key: 'activation',
      options: ['true', 'false', 'toggle'],
      required: true,
      defaultValue: 'true',
    ),
  ],
);
const _profileResultSchema = DartDataInputSchema(
  label: 'Returns',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Profile ID',
      key: 'profileId',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      label: 'Active',
      key: 'active',
      kind: DartDataInputKind.boolean,
    ),
  ],
);
const _runAutomationSchema = DartDataInputSchema(
  label: '',
  kind: DartDataInputKind.object,
  fields: [_automationReference],
);

typedef ShowRunnerAutomationLoader =
    Future<AutomationData?> Function(String automationId);
typedef ShowRunnerAutomationRunner =
    Future<Object?> Function(
      AutomationData automation,
      EvaluationContext context,
    );
typedef ShowRunnerProfileActivation =
    Future<bool> Function(
      String profileId,
      String activation,
      EvaluationContext context,
    );

DartPluginManifest createShowRunnerPlugin({
  DartAutomationQueueManager? queueManager,
  ShowRunnerAutomationLoader? loadAutomation,
  ShowRunnerAutomationRunner? runAutomation,
  ShowRunnerProfileActivation? activateProfile,
}) => DartPluginManifest(
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
    DartActionDefinition(
      pluginId: 'ShowRunner',
      actionId: 'addToQueue',
      displayName: 'Add to Queue',
      configSchema: _addToQueueSchema,
      resultSchema: _queueResultSchema,
      invoke: (config, context) => _addToQueue(
        config,
        context,
        queueManager: queueManager,
        loadAutomation: loadAutomation,
      ),
    ),
    DartActionDefinition(
      pluginId: 'ShowRunner',
      actionId: 'completeQueueItem',
      displayName: 'Complete Queue Item',
      resultSchema: _completedQueueResultSchema,
      invoke: (config, context) async => {'completed': true},
    ),
    DartActionDefinition(
      pluginId: 'ShowRunner',
      actionId: 'cancelQueueItem',
      displayName: 'Cancel Queue Item',
      configSchema: _queueControlSchema,
      invoke: (config, context) => _cancelQueueItem(config, queueManager),
    ),
    DartActionDefinition(
      pluginId: 'ShowRunner',
      actionId: 'clearQueue',
      displayName: 'Clear Queue',
      configSchema: _queueControlSchema,
      invoke: (config, context) => _clearQueue(config, queueManager),
    ),
    DartActionDefinition(
      pluginId: 'ShowRunner',
      actionId: 'skip',
      displayName: 'Queue Skip',
      configSchema: _queueControlSchema,
      invoke: (config, context) => _cancelQueueItem(config, queueManager),
    ),
    DartActionDefinition(
      pluginId: 'ShowRunner',
      actionId: 'pause',
      displayName: 'Pause Queue',
      configSchema: _pauseQueueSchema,
      invoke: (config, context) => _pauseQueue(config, queueManager),
    ),
    DartActionDefinition(
      pluginId: 'ShowRunner',
      actionId: 'profileActivation',
      displayName: 'Profile Activation',
      configSchema: _profileActivationSchema,
      resultSchema: _profileResultSchema,
      invoke: (config, context) =>
          _activateProfile(config, context, activateProfile: activateProfile),
    ),
    DartActionDefinition(
      pluginId: 'ShowRunner',
      actionId: 'toggleProfileActivation',
      displayName: 'Toggle Profile Activation',
      configSchema: const DartDataInputSchema(
        label: '',
        kind: DartDataInputKind.object,
        fields: [_profileReference],
      ),
      resultSchema: _profileResultSchema,
      invoke: (config, context) => _activateProfile(
        config,
        context,
        activateProfile: activateProfile,
        forceToggle: true,
      ),
    ),
    DartActionDefinition(
      pluginId: 'ShowRunner',
      actionId: 'runAutomation',
      displayName: 'Run Automation',
      configSchema: _runAutomationSchema,
      invoke: (config, context) => _runAutomationAction(
        config,
        context,
        loadAutomation: loadAutomation,
        runAutomation: runAutomation,
      ),
    ),
  ],
  triggers: [
    DartTriggerDefinition(
      pluginId: 'ShowRunner',
      triggerId: 'autoRun',
      displayName: 'Run On Change',
      listen: Stream<RuntimeMap>.empty,
      configSchema: _autoRunSchema,
    ),
    DartTriggerDefinition(
      pluginId: 'ShowRunner',
      triggerId: 'condition',
      displayName: 'Condition',
      listen: Stream<RuntimeMap>.empty,
      configSchema: _conditionTriggerSchema,
    ),
    if (queueManager != null)
      DartTriggerDefinition(
        pluginId: 'ShowRunner',
        triggerId: 'queueItemStarted',
        displayName: 'Queue Item Started',
        listen: () => queueManager.queueItemStarted,
        listenForConfig: (config) {
          final queueId = config['queue']?.toString().trim();
          final stream = queueManager.queueItemStarted;
          return queueId == null || queueId.isEmpty
              ? stream
              : stream.where((event) => event['queueId'] == queueId);
        },
        configSchema: _queueTriggerSchema,
      ),
  ],
);

Future<Object?> _addToQueue(
  RuntimeMap config,
  EvaluationContext context, {
  required DartAutomationQueueManager? queueManager,
  required ShowRunnerAutomationLoader? loadAutomation,
}) async {
  final queueId = config['queue']?.toString().trim() ?? '';
  final automationId = config['automation']?.toString().trim() ?? '';
  if (queueManager == null ||
      loadAutomation == null ||
      queueId.isEmpty ||
      automationId.isEmpty) {
    return {'queued': false, 'queueId': '', 'automationId': ''};
  }
  final automation = await loadAutomation(automationId);
  if (automation == null) {
    return {'queued': false, 'queueId': queueId, 'automationId': automationId};
  }
  final payload = config['payload'] is Map
      ? Map<String, dynamic>.from(config['payload'] as Map)
      : context.contextState;
  final queued = await queueManager.enqueue(
    automation,
    EvaluationContext(
      locals: context.locals,
      contextState: {
        'payload': payload,
        'queuedAt': DateTime.now().toIso8601String(),
        'source': {'type': 'graph', 'action': 'addToQueue'},
      },
    ),
    queueId: queueId,
    sourceMetadata: {'sourceType': 'automation', 'sourceId': automationId},
  );
  return {
    'queued': true,
    'queueId': queueId,
    'automationId': automationId,
    'itemId': queued.id,
  };
}

Future<Object?> _activateProfile(
  RuntimeMap config,
  EvaluationContext context, {
  required ShowRunnerProfileActivation? activateProfile,
  bool forceToggle = false,
}) async {
  final profileId = config['profile']?.toString().trim() ?? '';
  if (activateProfile == null || profileId.isEmpty) {
    return {'profileId': profileId, 'active': false};
  }
  final activation = forceToggle
      ? 'toggle-active'
      : _activationValue(config['activation']);
  final active = await activateProfile(profileId, activation, context);
  return {'profileId': profileId, 'active': active};
}

Future<Object?> _runAutomationAction(
  RuntimeMap config,
  EvaluationContext context, {
  required ShowRunnerAutomationLoader? loadAutomation,
  required ShowRunnerAutomationRunner? runAutomation,
}) async {
  final automationId = config['automation']?.toString().trim() ?? '';
  if (loadAutomation == null || runAutomation == null || automationId.isEmpty) {
    return {'ran': false, 'automationId': automationId};
  }
  final automation = await loadAutomation(automationId);
  if (automation == null) {
    return {'ran': false, 'automationId': automationId};
  }
  await runAutomation(automation, context);
  return {'ran': true, 'automationId': automationId};
}

String _activationValue(dynamic value) {
  if (value == true || value == 'true') return 'true';
  if (value == false || value == 'false') return 'false';
  return 'toggle';
}

Future<Object?> _cancelQueueItem(
  RuntimeMap config,
  DartAutomationQueueManager? queueManager,
) async {
  final queue = await _resolveQueue(config, queueManager);
  final running = queue?.running;
  if (running != null) await queue?.cancelRunning();
  return {'cancelled': running != null};
}

Future<Object?> _clearQueue(
  RuntimeMap config,
  DartAutomationQueueManager? queueManager,
) async {
  final queue = await _resolveQueue(config, queueManager);
  queue?.clearPending();
  return {'cleared': queue != null};
}

Future<Object?> _pauseQueue(
  RuntimeMap config,
  DartAutomationQueueManager? queueManager,
) async {
  final queueId = config['queue']?.toString().trim() ?? '';
  final queue = await _resolveQueue(config, queueManager);
  if (queue == null) return {'paused': false};
  final value = config['paused'];
  final paused = value == 'toggle' || value == null
      ? !queue.paused
      : value == true || value == 'true';
  if (queueManager == null || queueId.isEmpty) {
    queue.setPaused(paused);
  } else {
    await queueManager.setPaused(queueId, paused);
  }
  return {'paused': paused};
}

Future<DartActionQueue?> _resolveQueue(
  RuntimeMap config,
  DartAutomationQueueManager? queueManager,
) {
  final queueId = config['queue']?.toString().trim();
  if (queueManager == null || queueId == null || queueId.isEmpty) {
    return Future.value(null);
  }
  return queueManager.queueFor(queueId);
}

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
