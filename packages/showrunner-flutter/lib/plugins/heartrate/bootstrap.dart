import '../../services/plugin_event_hub.dart';
import '../../services/showrunner_data_service.dart';
import '../registry/plugin_registry.dart';
import 'ble/fake_transport.dart';
import 'ble/universal_ble_transport.dart';
import 'manifest.dart';
import 'services/heart_rate_service.dart';
import 'ui/plugin_ui.dart';

HeartRateService registerHeartRatePlugin(
  DartPluginRegistry registry, {
  ShowRunnerDataService? dataService,
  DartPluginEventHub? eventHub,
}) {
  final service = createHeartRateService(
    transport: dataService == null
        ? FakeBleTransport()
        : UniversalBleTransport(),
    eventHub: eventHub,
    loadSettings: dataService == null
        ? null
        : () => dataService.loadPluginSettings('heartrate'),
    saveSettings: dataService == null
        ? null
        : (settings) => dataService.savePluginSettings('heartrate', settings),
    onStateChanged: (stateId, value) =>
        registry.updateState('heartrate', stateId, value),
  );
  registry.registerModule(createHeartRatePluginModule(service));
  registry.registerUi('heartrate', createHeartRatePluginUi(service));
  return service;
}
