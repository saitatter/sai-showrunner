import '../../schema/data_input.dart';
import '../registry/plugin_contract.dart';
import '../registry/plugin_health.dart';
import '../registry/plugin_host_context.dart';
import '../registry/plugin_module.dart';
import 'ble/fake_transport.dart';
import 'ble/transport.dart';
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
  Future<Map<String, dynamic>> Function()? loadSettings,
  Future<void> Function(Map<String, dynamic> settings)? saveSettings,
  void Function(String stateId, dynamic value)? onStateChanged,
}) => HeartRateService(
  transport: transport ?? FakeBleTransport(),
  loadSettings: loadSettings,
  saveSettings: saveSettings,
  onStateChanged: onStateChanged,
);

int? _asInt(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value');
