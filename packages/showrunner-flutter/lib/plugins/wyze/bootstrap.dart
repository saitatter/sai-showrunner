import 'dart:async';
import '../../runtime/expression.dart';
import '../../services/showrunner_data_service.dart';
import '../registry/plugin_registry.dart';
import 'account_runtime.dart';
import 'manifest.dart';

Future<void> registerConfiguredWyze(
  DartPluginRegistry registry, {
  required ShowRunnerDataService dataService,
}) async {
  final wyzeSettings = await loadWyzeAccountSettings(dataService);
  final wyzeTransport = WyzeHttpTransport(
    keyId: wyzeSettings['keyId']?.toString() ?? '',
    apiKey: wyzeSettings['apiKey']?.toString() ?? '',
    accessToken: wyzeSettings['accessToken']?.toString(),
    refreshToken: wyzeSettings['refreshToken']?.toString(),
    onTokens: (tokens) async {
      await saveWyzeAccountTokens(
        dataService,
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
    },
  );
  registry.register(
    createWyzePlugin(wyzeTransport),
    onStop: wyzeTransport.close,
  );
}

void registerDefaultWyze(DartPluginRegistry registry) {
  registry.register(
    createWyzePlugin(_unconfiguredWyzeTransport),
    onStop: _unconfiguredWyzeTransport.close,
  );
}

final WyzeTransport _unconfiguredWyzeTransport = CallbackWyzeTransport(
  loginCallback: (email, password) =>
      Future<WyzeToken>.error(StateError('Wyze transport is not configured.')),
  getDevicesCallback: () => Future<List<RuntimeMap>>.error(
    StateError('Wyze transport is not configured.'),
  ),
  getDeviceStateCallback: (mac, model) =>
      Future<RuntimeMap>.error(StateError('Wyze transport is not configured.')),
  setLightStateCallback: (mac, model, properties) =>
      Future<RuntimeMap>.error(StateError('Wyze transport is not configured.')),
  setPlugStateCallback: (mac, model, on) =>
      Future<RuntimeMap>.error(StateError('Wyze transport is not configured.')),
);
