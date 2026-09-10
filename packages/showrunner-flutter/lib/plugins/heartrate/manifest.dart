import 'dart:async';

import '../../schema/data_input.dart';
import '../../runtime/expression.dart';
import '../../services/plugin_event_hub.dart';
import '../registry/plugin_contract.dart';
import '../registry/plugin_health.dart';
import '../registry/plugin_host_context.dart';
import '../registry/plugin_module.dart';
import 'ble/fake_transport.dart';
import 'ble/transport.dart';
import 'events.dart';
import 'services/heart_rate_service.dart';

const _emptyObjectSchema = DartDataInputSchema(
  label: 'Heart Rate configuration',
  kind: DartDataInputKind.object,
);

const _simulationSchema = DartDataInputSchema(
  label: 'Heart Rate simulation',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      key: 'bpm',
      label: 'BPM',
      kind: DartDataInputKind.number,
      defaultValue: 124,
    ),
    DartDataInputSchema(
      key: 'batteryPercent',
      label: 'Battery percent',
      kind: DartDataInputKind.number,
      defaultValue: 86,
    ),
  ],
);

final class HeartRatePluginModule implements DartPluginModule {
  HeartRatePluginModule(this.service);

  final HeartRateService service;

  @override
  DartPluginManifest get manifest => createHeartRatePlugin(service);

  @override
  Future<void> initialize(DartPluginHostContext host) => service.initialize();

  @override
  Future<void> start() => service.start();

  @override
  Future<void> stop() => service.close();

  @override
  Future<DartPluginHealth> checkHealth() async {
    late final BleAdapterState adapter;
    try {
      adapter = await service.transport.getAdapterState();
    } on Object {
      return const DartPluginHealth(
        status: DartPluginHealthStatus.unavailable,
        message: 'Bluetooth adapter could not be accessed.',
      );
    }
    return adapter == BleAdapterState.poweredOn
        ? const DartPluginHealth.ready()
        : const DartPluginHealth(
            status: DartPluginHealthStatus.unavailable,
            message: 'Bluetooth adapter is not available.',
          );
  }
}

DartPluginManifest createHeartRatePlugin(HeartRateService service) =>
    DartPluginManifest(
      id: PluginId('heartrate'),
      name: 'Heart Rate',
      version: '0.1.0',
      settings: const [
        SettingSpec<bool>(
          id: SettingId('autoConnect'),
          displayName: 'Auto-connect preferred device',
          defaultValue: false,
          type: DartSettingType.boolean,
        ),
        SettingSpec<bool>(
          id: SettingId('scanHeartRateOnly'),
          displayName: 'Show heart-rate devices only',
          defaultValue: true,
          type: DartSettingType.boolean,
        ),
        SettingSpec<bool>(
          id: SettingId('reconnectEnabled'),
          displayName: 'Reconnect after disconnect',
          defaultValue: true,
          type: DartSettingType.boolean,
        ),
        SettingSpec<int>(
          id: SettingId('staleAfterMs'),
          displayName: 'Stale data timeout (ms)',
          defaultValue: 3000,
          type: DartSettingType.number,
        ),
        SettingSpec<int>(
          id: SettingId('batteryPollSeconds'),
          displayName: 'Battery refresh interval (seconds)',
          defaultValue: 30,
          type: DartSettingType.number,
        ),
        SettingSpec<String>(
          id: SettingId('preferredDeviceId'),
          displayName: 'Preferred device ID',
        ),
        SettingSpec<String>(
          id: SettingId('preferredDeviceName'),
          displayName: 'Preferred device name',
        ),
      ],
      actions: [
        ActionSpec<Map<String, dynamic>, Object?>(
          pluginId: PluginId('heartrate'),
          actionId: ActionId('connectPreferredDevice'),
          displayName: 'Connect Preferred Device',
          configSchema: _emptyObjectSchema,
          invoke: (config, context) => service.connectPreferredDevice(),
        ),
        ActionSpec<Map<String, dynamic>, Object?>(
          pluginId: PluginId('heartrate'),
          actionId: ActionId('disconnect'),
          displayName: 'Disconnect Heart Rate Device',
          configSchema: _emptyObjectSchema,
          invoke: (config, context) => service.disconnect(),
        ),
        ActionSpec<Map<String, dynamic>, Object?>(
          pluginId: PluginId('heartrate'),
          actionId: ActionId('startSimulation'),
          displayName: 'Start Heart Rate Simulation',
          configSchema: _simulationSchema,
          invoke: (config, context) => service.startSimulation(
            bpm: _asInt(config['bpm']) ?? 124,
            batteryPercent: _asInt(config['batteryPercent']) ?? 86,
          ),
        ),
        ActionSpec<Map<String, dynamic>, Object?>(
          pluginId: PluginId('heartrate'),
          actionId: ActionId('stopSimulation'),
          displayName: 'Stop Heart Rate Simulation',
          configSchema: _emptyObjectSchema,
          invoke: (config, context) => service.stopSimulation(),
        ),
        ActionSpec<Map<String, dynamic>, Object?>(
          pluginId: PluginId('heartrate'),
          actionId: ActionId('resetStatistics'),
          displayName: 'Reset Heart Rate Statistics',
          configSchema: _emptyObjectSchema,
          invoke: (config, context) async => service.resetStatistics(),
        ),
      ],
      triggers: service.eventHub == null
          ? const []
          : [
              TriggerSpec<Map<String, dynamic>, Map<String, dynamic>>(
                pluginId: PluginId('heartrate'),
                triggerId: TriggerId('deviceConnected'),
                displayName: 'Device Connected',
                listen: () =>
                    service.eventHub!.stream(HeartRateEventIds.deviceConnected),
                eventSchema: _deviceConnectedEventSchema,
              ),
              TriggerSpec<Map<String, dynamic>, Map<String, dynamic>>(
                pluginId: PluginId('heartrate'),
                triggerId: TriggerId('deviceDisconnected'),
                displayName: 'Device Disconnected',
                listen: () => service.eventHub!.stream(
                  HeartRateEventIds.deviceDisconnected,
                ),
                eventSchema: _deviceDisconnectedEventSchema,
              ),
              TriggerSpec<Map<String, dynamic>, Map<String, dynamic>>(
                pluginId: PluginId('heartrate'),
                triggerId: TriggerId('zoneChanged'),
                displayName: 'Zone Changed',
                listen: () =>
                    service.eventHub!.stream(HeartRateEventIds.zoneChanged),
                eventSchema: _zoneChangedEventSchema,
              ),
              TriggerSpec<Map<String, dynamic>, Map<String, dynamic>>(
                pluginId: PluginId('heartrate'),
                triggerId: TriggerId('above'),
                displayName: 'Heart Rate Above',
                configSchema: _thresholdSchema,
                listen: _emptyTrigger,
                listenForConfig: (config) =>
                    _thresholdEvents(service.eventHub!, config, above: true),
                eventSchema: _thresholdEventSchema,
              ),
              TriggerSpec<Map<String, dynamic>, Map<String, dynamic>>(
                pluginId: PluginId('heartrate'),
                triggerId: TriggerId('below'),
                displayName: 'Heart Rate Below',
                configSchema: _thresholdSchema,
                listen: _emptyTrigger,
                listenForConfig: (config) =>
                    _thresholdEvents(service.eventHub!, config, above: false),
                eventSchema: _thresholdEventSchema,
              ),
            ],
      states: const [
        StateSpec<Map<String, dynamic>>(
          id: StateId('connection'),
          displayName: 'Connection',
          initialValue: {'status': 'idle', 'simulated': false},
        ),
        StateSpec<Map<String, dynamic>>(
          id: StateId('heartRate'),
          displayName: 'Heart Rate',
          initialValue: {'stale': true, 'rrIntervalsMs': <double>[]},
        ),
        StateSpec<Map<String, dynamic>>(
          id: StateId('device'),
          displayName: 'Device',
          initialValue: {'connected': false},
        ),
        StateSpec<Map<String, dynamic>>(
          id: StateId('zone'),
          displayName: 'Zone',
          initialValue: {},
        ),
      ],
    );

HeartRatePluginModule createHeartRatePluginModule(HeartRateService service) =>
    HeartRatePluginModule(service);

HeartRateService createHeartRateService({
  BleTransport? transport,
  DartPluginEventHub? eventHub,
  Future<Map<String, dynamic>> Function()? loadSettings,
  Future<void> Function(Map<String, dynamic> settings)? saveSettings,
  void Function(String stateId, dynamic value)? onStateChanged,
}) => HeartRateService(
  transport: transport ?? FakeBleTransport(),
  eventHub: eventHub,
  loadSettings: loadSettings,
  saveSettings: saveSettings,
  onStateChanged: onStateChanged,
);

int? _asInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value');

const _thresholdSchema = DartDataInputSchema(
  label: 'Heart-rate threshold',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      key: 'threshold',
      label: 'Threshold (BPM)',
      kind: DartDataInputKind.number,
      required: true,
      defaultValue: 150,
    ),
    DartDataInputSchema(
      key: 'hysteresis',
      label: 'Hysteresis (BPM)',
      kind: DartDataInputKind.number,
      defaultValue: 3,
    ),
    DartDataInputSchema(
      key: 'cooldownSeconds',
      label: 'Cooldown (seconds)',
      kind: DartDataInputKind.number,
      defaultValue: 0,
    ),
  ],
);

const _deviceConnectedEventSchema = DartDataInputSchema(
  label: 'Connected device event',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      key: 'deviceName',
      label: 'Device name',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      key: 'battery',
      label: 'Battery percent',
      kind: DartDataInputKind.number,
    ),
  ],
);

const _deviceDisconnectedEventSchema = DartDataInputSchema(
  label: 'Disconnected device event',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      key: 'deviceName',
      label: 'Device name',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      key: 'reason',
      label: 'Reason',
      kind: DartDataInputKind.text,
    ),
  ],
);

const _zoneChangedEventSchema = DartDataInputSchema(
  label: 'Zone change event',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      key: 'bpm',
      label: 'BPM',
      kind: DartDataInputKind.number,
    ),
    DartDataInputSchema(
      key: 'previousZone',
      label: 'Previous zone',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      key: 'zone',
      label: 'Zone',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      key: 'zoneIndex',
      label: 'Zone index',
      kind: DartDataInputKind.number,
    ),
  ],
);

const _thresholdEventSchema = DartDataInputSchema(
  label: 'Threshold event',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      key: 'bpm',
      label: 'BPM',
      kind: DartDataInputKind.number,
    ),
    DartDataInputSchema(
      key: 'threshold',
      label: 'Threshold',
      kind: DartDataInputKind.number,
    ),
  ],
);

Stream<RuntimeMap> _emptyTrigger() => const Stream<RuntimeMap>.empty();

Stream<RuntimeMap> _thresholdEvents(
  DartPluginEventHub hub,
  RuntimeMap config, {
  required bool above,
}) {
  final threshold = _number(config['threshold'], fallback: 150);
  final hysteresis = _number(config['hysteresis'], fallback: 3).clamp(0, 1000);
  final cooldown = Duration(
    seconds: _number(
      config['cooldownSeconds'],
      fallback: 0,
    ).clamp(0, 86400).toInt(),
  );
  bool? latched;
  DateTime? lastFired;
  late final StreamSubscription<RuntimeMap> subscription;
  late final StreamController<RuntimeMap> controller;
  controller = StreamController<RuntimeMap>(
    onListen: () {
      subscription = hub.stream(HeartRateEventIds.measurement).listen((event) {
        final value = _number(event['bpm'], fallback: 0);
        final entry = above ? value >= threshold : value <= threshold;
        final rearm = above
            ? value < threshold - hysteresis
            : value > threshold + hysteresis;
        if (latched == null) {
          latched = entry;
          return;
        }
        if (latched == true && rearm) {
          latched = false;
          return;
        }
        if (latched == true || !entry) return;
        final now = DateTime.now();
        final firedAt = lastFired;
        if (firedAt != null && now.difference(firedAt) < cooldown) {
          latched = true;
          return;
        }
        latched = true;
        lastFired = now;
        controller.add({'bpm': value, 'threshold': threshold});
      });
    },
    onCancel: () => subscription.cancel(),
  );
  return controller.stream;
}

num _number(Object? value, {required num fallback}) =>
    value is num ? value : num.tryParse('$value') ?? fallback;
