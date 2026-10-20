import '../runtime/provider_operation_policy.dart';
import 'dart:async';
import 'dart:io';
import '../../runtime/expression.dart';
import '../../services/showrunner_data_service.dart';
import '../registry/plugin_registry.dart';
import 'manifest.dart';
import 'resource_sync.dart';

Future<void> registerConfiguredPhilipsHue(
  DartPluginRegistry registry, {
  required ShowRunnerDataService dataService,
}) async {
  final scope = ProviderOperationScope();
  final hueSettings = await dataService.loadPluginSettings('philips-hue');
  final hueIp = hueSettings['hubIp']?.toString().trim() ?? '';
  final hueKey = hueSettings['hubKey']?.toString().trim() ?? '';
  final hueTransport = hueIp.isNotEmpty && hueKey.isNotEmpty
      ? HueHttpTransport(scope: scope, host: hueIp, applicationKey: hueKey)
      : null;
  final configuredHueTransport = HueTransport(
    hueTransport?.request ?? _unconfiguredPhilipsHue,
  );
  registry.register(
    createPhilipsHuePlugin(
      configuredHueTransport,
      transportResolver: (config) {
        final host = config['host']?.toString().trim() ?? '';
        final key = config['hubKey']?.toString().trim() ?? '';
        if (host.isEmpty || (key.isEmpty && hueKey.isEmpty)) {
          return configuredHueTransport;
        }
        return HueTransport(
          HueHttpTransport(
            scope: scope,
            host: host,
            applicationKey: key.isEmpty ? hueKey : key,
          ).request,
        );
      },
    ),

    initialHealth: (hueTransport != null)
        ? const DartPluginHealth.connectionUnchecked()
        : const DartPluginHealth.notConfigured(),
    onStop: scope.close,
    onStart: () async {
      if (hueTransport != null) {
        try {
          await PhilipsHueResourceSynchronizer(
            lightDirectory: Directory(
              '${dataService.userDirectory.path}/iot/lights',
            ),
            plugDirectory: Directory(
              '${dataService.userDirectory.path}/iot/plugs',
            ),
            secretSettings: dataService.secretSettingsStore,
          ).sync(configuredHueTransport);
        } catch (_) {
          // Resource discovery is best effort; actions can still use manually
          // configured Hue resources when the bridge is temporarily offline.
        }
      }
    },
  );
}

void registerDefaultPhilipsHue(DartPluginRegistry registry) {
  registry.register(
    createPhilipsHuePlugin(HueTransport(_unconfiguredPhilipsHue)),

    initialHealth: const DartPluginHealth.notConfigured(),
  );
}

Future<RuntimeMap> _unconfiguredPhilipsHue(
  String method,
  String path,
  RuntimeMap query,
  dynamic body,
) => Future<RuntimeMap>.error(
  StateError('Philips Hue transport is not configured.'),
);
