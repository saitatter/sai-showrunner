import 'dart:convert';

import '../../schema/data_input.dart';
import '../../schema/automation.dart';
import '../../runtime/automation_queue_manager.dart';
import '../../runtime/action_queue.dart';
import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';
import 'contracts.dart';

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
  resourceType: ResourceTypeId('ActionQueue'),
);
const _optionalQueueReference = DartDataInputSchema(
  label: 'Queue',
  kind: DartDataInputKind.resource,
  key: 'queue',
  resourceType: ResourceTypeId('ActionQueue'),
);
const _automationReference = DartDataInputSchema(
  label: 'Worker Automation',
  kind: DartDataInputKind.resource,
  key: 'automation',
  required: true,
  resourceType: ResourceTypeId('Automation'),
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
  resourceType: ResourceTypeId('Profile'),
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
  id: PluginId('ShowRunner'),
  name: 'ShowRunner',
  settings: [
    SettingSpec(
      id: SettingId('port'),
      displayName: 'Internal Webserver Port',
      defaultValue: 8181,
    ),
  ],
  actions: [
    ActionSpec<ShowRunnerNumberValueConfig, RuntimeMap>(
      pluginId: PluginId('ShowRunner'),
      actionId: ActionId('convertNumberToString'),
      displayName: 'Convert Number To String',
      invoke: _convertNumberToString,
      configCodec: showRunnerNumberValueConfigCodec,
      resultSchema: _stringResult,
      configSchema: DartDataInputSchema(
        label: '',
        kind: DartDataInputKind.object,
        fields: [_numberValue],
      ),
    ),
    ActionSpec<ShowRunnerBooleanValueConfig, RuntimeMap>(
      pluginId: PluginId('ShowRunner'),
      actionId: ActionId('convertBooleanToString'),
      displayName: 'Convert Boolean To String',
      invoke: _convertBooleanToString,
      configCodec: showRunnerBooleanValueConfigCodec,
      resultSchema: _stringResult,
      configSchema: DartDataInputSchema(
        label: '',
        kind: DartDataInputKind.object,
        fields: [_booleanValue],
      ),
    ),
    ActionSpec<ShowRunnerStringToNumberConfig, RuntimeMap>(
      pluginId: PluginId('ShowRunner'),
      actionId: ActionId('convertStringToNumber'),
      displayName: 'Convert String To Number',
      invoke: _convertStringToNumber,
      configCodec: showRunnerStringToNumberConfigCodec,
      resultSchema: _numberConversionResult,
      configSchema: DartDataInputSchema(
        label: '',
        kind: DartDataInputKind.object,
        fields: [_textValue, _fallbackNumber],
      ),
    ),
    ActionSpec<ShowRunnerBooleanValueConfig, RuntimeMap>(
      pluginId: PluginId('ShowRunner'),
      actionId: ActionId('convertBooleanToNumber'),
      displayName: 'Convert Boolean To Number',
      invoke: _convertBooleanToNumber,
      configCodec: showRunnerBooleanValueConfigCodec,
      resultSchema: _numberResult,
      configSchema: DartDataInputSchema(
        label: '',
        kind: DartDataInputKind.object,
        fields: [_booleanValue],
      ),
    ),
    ActionSpec<ShowRunnerNumberValueConfig, RuntimeMap>(
      pluginId: PluginId('ShowRunner'),
      actionId: ActionId('convertNumberToBoolean'),
      displayName: 'Convert Number To Boolean',
      invoke: _convertNumberToBoolean,
      configCodec: showRunnerNumberValueConfigCodec,
      resultSchema: _booleanResult,
      configSchema: DartDataInputSchema(
        label: '',
        kind: DartDataInputKind.object,
        fields: [_numberValue],
      ),
    ),
    ActionSpec<ShowRunnerStringToBooleanConfig, RuntimeMap>(
      pluginId: PluginId('ShowRunner'),
      actionId: ActionId('convertStringToBoolean'),
      displayName: 'Convert String To Boolean',
      invoke: _convertStringToBoolean,
      configCodec: showRunnerStringToBooleanConfigCodec,
      resultSchema: _booleanConversionResult,
      configSchema: DartDataInputSchema(
        label: '',
        kind: DartDataInputKind.object,
        fields: [_textValue, _fallbackBoolean],
      ),
    ),
    ActionSpec<ShowRunnerObjectConfig, RuntimeMap>(
      pluginId: PluginId('ShowRunner'),
      actionId: ActionId('convertObjectToJsonString'),
      displayName: 'Convert Object To JSON String',
      invoke: _convertObjectToJsonString,
      configCodec: showRunnerObjectConfigCodec,
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
    ActionSpec<ShowRunnerArrayConfig, RuntimeMap>(
      pluginId: PluginId('ShowRunner'),
      actionId: ActionId('convertArrayToJsonString'),
      displayName: 'Convert Array To JSON String',
      invoke: _convertArrayToJsonString,
      configCodec: showRunnerArrayConfigCodec,
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
    ActionSpec<ShowRunnerJsonConfig, RuntimeMap>(
      pluginId: PluginId('ShowRunner'),
      actionId: ActionId('convertJsonStringToObject'),
      displayName: 'Convert JSON String To Object',
      invoke: _convertJsonStringToObject,
      configCodec: showRunnerJsonConfigCodec,
      resultSchema: _objectConversionResult,
      configSchema: DartDataInputSchema(
        label: '',
        kind: DartDataInputKind.object,
        fields: [_jsonValue],
      ),
    ),
    ActionSpec<ShowRunnerJsonConfig, RuntimeMap>(
      pluginId: PluginId('ShowRunner'),
      actionId: ActionId('convertJsonStringToArray'),
      displayName: 'Convert JSON String To Array',
      invoke: _convertJsonStringToArray,
      configCodec: showRunnerJsonConfigCodec,
      resultSchema: _arrayConversionResult,
      configSchema: DartDataInputSchema(
        label: '',
        kind: DartDataInputKind.object,
        fields: [_jsonValue],
      ),
    ),
    ActionSpec<ShowRunnerAddToQueueConfig, RuntimeMap>(
      pluginId: PluginId('ShowRunner'),
      actionId: ActionId('addToQueue'),
      displayName: 'Add to Queue',
      configSchema: _addToQueueSchema,
      resultSchema: _queueResultSchema,
      invoke: (config, context) => _addToQueue(
        config,
        context,
        queueManager: queueManager,
        loadAutomation: loadAutomation,
      ),
      configCodec: showRunnerAddToQueueConfigCodec,
    ),
    ActionSpec<ShowRunnerEmptyConfig, RuntimeMap>(
      pluginId: PluginId('ShowRunner'),
      actionId: ActionId('completeQueueItem'),
      displayName: 'Complete Queue Item',
      resultSchema: _completedQueueResultSchema,
      invoke: (config, context) async => {'completed': true},
      configCodec: showRunnerEmptyConfigCodec,
    ),
    ActionSpec<ShowRunnerQueueConfig, RuntimeMap>(
      pluginId: PluginId('ShowRunner'),
      actionId: ActionId('cancelQueueItem'),
      displayName: 'Cancel Queue Item',
      configSchema: _queueControlSchema,
      configCodec: showRunnerQueueConfigCodec,
      invoke: (config, context) => _cancelQueueItem(config, queueManager),
    ),
    ActionSpec<ShowRunnerQueueConfig, RuntimeMap>(
      pluginId: PluginId('ShowRunner'),
      actionId: ActionId('clearQueue'),
      displayName: 'Clear Queue',
      configSchema: _queueControlSchema,
      configCodec: showRunnerQueueConfigCodec,
      invoke: (config, context) => _clearQueue(config, queueManager),
    ),
    ActionSpec<ShowRunnerQueueConfig, RuntimeMap>(
      pluginId: PluginId('ShowRunner'),
      actionId: ActionId('skip'),
      displayName: 'Queue Skip',
      configSchema: _queueControlSchema,
      configCodec: showRunnerQueueConfigCodec,
      invoke: (config, context) => _cancelQueueItem(config, queueManager),
    ),
    ActionSpec<ShowRunnerPauseQueueConfig, RuntimeMap>(
      pluginId: PluginId('ShowRunner'),
      actionId: ActionId('pause'),
      displayName: 'Pause Queue',
      configSchema: _pauseQueueSchema,
      configCodec: showRunnerPauseQueueConfigCodec,
      invoke: (config, context) => _pauseQueue(config, queueManager),
    ),
    ActionSpec<ShowRunnerProfileActivationConfig, RuntimeMap>(
      pluginId: PluginId('ShowRunner'),
      actionId: ActionId('profileActivation'),
      displayName: 'Profile Activation',
      configSchema: _profileActivationSchema,
      configCodec: showRunnerProfileActivationConfigCodec,
      resultSchema: _profileResultSchema,
      invoke: (config, context) =>
          _activateProfile(config, context, activateProfile: activateProfile),
    ),
    ActionSpec<ShowRunnerProfileActivationConfig, RuntimeMap>(
      pluginId: PluginId('ShowRunner'),
      actionId: ActionId('toggleProfileActivation'),
      displayName: 'Toggle Profile Activation',
      configSchema: const DartDataInputSchema(
        label: '',
        kind: DartDataInputKind.object,
        fields: [_profileReference],
      ),
      configCodec: showRunnerProfileActivationConfigCodec,
      resultSchema: _profileResultSchema,
      invoke: (config, context) => _activateProfile(
        config,
        context,
        activateProfile: activateProfile,
        forceToggle: true,
      ),
    ),
    ActionSpec<ShowRunnerAutomationConfig, RuntimeMap>(
      pluginId: PluginId('ShowRunner'),
      actionId: ActionId('runAutomation'),
      displayName: 'Run Automation',
      configSchema: _runAutomationSchema,
      configCodec: showRunnerAutomationConfigCodec,
      invoke: (config, context) => _runAutomationAction(
        config,
        context,
        loadAutomation: loadAutomation,
        runAutomation: runAutomation,
      ),
    ),
  ],
  triggers: [
    TriggerSpec<ShowRunnerEmptyConfig, ShowRunnerEmptyConfig>(
      pluginId: PluginId('ShowRunner'),
      triggerId: TriggerId('autoRun'),
      displayName: 'Run On Change',
      listen: Stream<ShowRunnerEmptyConfig>.empty,
      configSchema: _autoRunSchema,
      configCodec: showRunnerEmptyConfigCodec,
      eventEncoder: (event) => event.toRuntime(),
    ),
    TriggerSpec<ShowRunnerConditionConfig, ShowRunnerEmptyConfig>(
      pluginId: PluginId('ShowRunner'),
      triggerId: TriggerId('condition'),
      displayName: 'Condition',
      listen: Stream<ShowRunnerEmptyConfig>.empty,
      configSchema: _conditionTriggerSchema,
      configCodec: showRunnerConditionConfigCodec,
      eventEncoder: (event) => event.toRuntime(),
    ),
    if (queueManager != null)
      TriggerSpec<ShowRunnerQueueConfig, ShowRunnerQueueItemStartedEvent>(
        pluginId: PluginId('ShowRunner'),
        triggerId: TriggerId('queueItemStarted'),
        displayName: 'Queue Item Started',
        listen: () => queueManager.queueItemStarted.map(
          ShowRunnerQueueItemStartedEvent.fromRuntime,
        ),
        listenForConfig: (config) {
          final queueId = config.queue?.trim();
          final stream = queueManager.queueItemStarted.map(
            ShowRunnerQueueItemStartedEvent.fromRuntime,
          );
          return queueId == null || queueId.isEmpty
              ? stream
              : stream.where((event) => event.queueId == queueId);
        },
        configSchema: _queueTriggerSchema,
        configCodec: showRunnerQueueConfigCodec,
        eventEncoder: (event) => event.toRuntime(),
      ),
  ],
);

Future<RuntimeMap> _addToQueue(
  ShowRunnerAddToQueueConfig config,
  EvaluationContext context, {
  required DartAutomationQueueManager? queueManager,
  required ShowRunnerAutomationLoader? loadAutomation,
}) async {
  final queueId = config.queue?.trim() ?? '';
  final automationId = config.automation?.trim() ?? '';
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
  final payload = config.payload ?? context.contextState;
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

Future<RuntimeMap> _activateProfile(
  ShowRunnerProfileActivationConfig config,
  EvaluationContext context, {
  required ShowRunnerProfileActivation? activateProfile,
  bool forceToggle = false,
}) async {
  final profileId = config.profile?.trim() ?? '';
  if (activateProfile == null || profileId.isEmpty) {
    return {'profileId': profileId, 'active': false};
  }
  final activation = forceToggle
      ? 'toggle-active'
      : _activationValue(config.activation);
  final active = await activateProfile(profileId, activation, context);
  return {'profileId': profileId, 'active': active};
}

Future<RuntimeMap> _runAutomationAction(
  ShowRunnerAutomationConfig config,
  EvaluationContext context, {
  required ShowRunnerAutomationLoader? loadAutomation,
  required ShowRunnerAutomationRunner? runAutomation,
}) async {
  final automationId = config.automation?.trim() ?? '';
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

String _activationValue(ShowRunnerToggleMode? value) => switch (value) {
  ShowRunnerToggleMode.enabled => 'true',
  ShowRunnerToggleMode.disabled => 'false',
  _ => 'toggle',
};

Future<RuntimeMap> _cancelQueueItem(
  ShowRunnerQueueConfig config,
  DartAutomationQueueManager? queueManager,
) async {
  final queue = await _resolveQueue(config.queue, queueManager);
  final running = queue?.running;
  if (running != null) await queue?.cancelRunning();
  return {'cancelled': running != null};
}

Future<RuntimeMap> _clearQueue(
  ShowRunnerQueueConfig config,
  DartAutomationQueueManager? queueManager,
) async {
  final queue = await _resolveQueue(config.queue, queueManager);
  queue?.clearPending();
  return {'cleared': queue != null};
}

Future<RuntimeMap> _pauseQueue(
  ShowRunnerPauseQueueConfig config,
  DartAutomationQueueManager? queueManager,
) async {
  final queueId = config.queue?.trim() ?? '';
  final queue = await _resolveQueue(config.queue, queueManager);
  if (queue == null) return {'paused': false};
  final paused =
      config.paused == ShowRunnerToggleMode.toggle || config.paused == null
      ? !queue.paused
      : config.paused == ShowRunnerToggleMode.enabled;
  if (queueManager == null || queueId.isEmpty) {
    queue.setPaused(paused);
  } else {
    await queueManager.setPaused(queueId, paused);
  }
  return {'paused': paused};
}

Future<DartActionQueue?> _resolveQueue(
  String? queueId,
  DartAutomationQueueManager? queueManager,
) {
  final normalizedQueueId = queueId?.trim();
  if (queueManager == null ||
      normalizedQueueId == null ||
      normalizedQueueId.isEmpty) {
    return Future.value(null);
  }
  return queueManager.queueFor(normalizedQueueId);
}

Future<RuntimeMap> _convertNumberToString(
  ShowRunnerNumberValueConfig config,
  EvaluationContext context,
) async => {'value': '${config.value}'};

Future<RuntimeMap> _convertBooleanToString(
  ShowRunnerBooleanValueConfig config,
  EvaluationContext context,
) async => {'value': config.value ? 'true' : 'false'};

Future<RuntimeMap> _convertStringToNumber(
  ShowRunnerStringToNumberConfig config,
  EvaluationContext context,
) async {
  final text = config.value.trim();
  final fallback = config.fallback;
  if (text.isEmpty) return {'value': fallback, 'converted': false};
  final parsed = num.tryParse(text);
  final converted = parsed != null && parsed.isFinite;
  return {'value': converted ? parsed : fallback, 'converted': converted};
}

Future<RuntimeMap> _convertBooleanToNumber(
  ShowRunnerBooleanValueConfig config,
  EvaluationContext context,
) async => {'value': config.value ? 1 : 0};

Future<RuntimeMap> _convertNumberToBoolean(
  ShowRunnerNumberValueConfig config,
  EvaluationContext context,
) async {
  return {'value': config.value.isFinite && config.value != 0};
}

Future<RuntimeMap> _convertStringToBoolean(
  ShowRunnerStringToBooleanConfig config,
  EvaluationContext context,
) async {
  final parsed = _parseBooleanText(config.value);
  return {'value': parsed ?? config.fallback, 'converted': parsed != null};
}

Future<RuntimeMap> _convertObjectToJsonString(
  ShowRunnerObjectConfig config,
  EvaluationContext context,
) async => {'value': _safeJsonStringify(config.value)};

Future<RuntimeMap> _convertArrayToJsonString(
  ShowRunnerArrayConfig config,
  EvaluationContext context,
) async => {'value': _safeJsonStringify(config.value)};

Future<RuntimeMap> _convertJsonStringToObject(
  ShowRunnerJsonConfig config,
  EvaluationContext context,
) async {
  final parsed = _safeJsonParse(config.value);
  final converted = parsed is Map;
  return {
    'value': converted
        ? Map<String, dynamic>.from(parsed)
        : <String, dynamic>{},
    'converted': converted,
  };
}

Future<RuntimeMap> _convertJsonStringToArray(
  ShowRunnerJsonConfig config,
  EvaluationContext context,
) async {
  final parsed = _safeJsonParse(config.value);
  final converted = parsed is List;
  return {'value': converted ? parsed : <dynamic>[], 'converted': converted};
}

bool? _parseBooleanText(dynamic value) {
  final normalized = '${value ?? ''}'.trim().toLowerCase();
  if (const {'true', '1', 'yes', 'y', 'on'}.contains(normalized)) return true;
  if (const {'false', '0', 'no', 'n', 'off'}.contains(normalized)) return false;
  return null;
}

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
