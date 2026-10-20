import 'dart:async';
import '../../runtime/expression.dart';
import '../../services/showrunner_data_service.dart';
import '../registry/plugin_factory_settings.dart';
import '../registry/plugin_registry.dart';
import 'manifest.dart';

Future<void> registerConfiguredElgato(
  DartPluginRegistry registry, {
  required ShowRunnerDataService dataService,
}) async {
  final elgatoSettings = await dataService.loadPluginSettings('elgato');
  final elgatoHost = elgatoSettings['host']?.toString().trim();
  final elgatoPort = pluginPort(elgatoSettings['port'], 9123);
  final elgatoLights = positivePluginInt(elgatoSettings['numberOfLights'], 1);
  final elgatoRgb =
      elgatoSettings['rgb'] == true ||
      elgatoSettings['rgb']?.toString().toLowerCase() == 'true';
  final elgatoTransport = elgatoHost?.isNotEmpty == true
      ? ElgatoHttpTransport(host: elgatoHost!, port: elgatoPort)
      : null;
  final configuredElgatoTransport = ElgatoTransport(
    elgatoTransport?.request ?? _unconfiguredElgato,
  );
  registry.register(
    createElgatoPlugin(
      configuredElgatoTransport,
      supportsRgb: elgatoRgb,
      numberOfLights: elgatoLights,
      transportResolver: (config) {
        final host = config['host']?.toString().trim() ?? '';
        if (host.isEmpty) return configuredElgatoTransport;
        return ElgatoTransport(
          ElgatoHttpTransport(
            host: host,
            port: pluginPort(config['port'], elgatoPort),
          ).request,
        );
      },
    ),
  );
}

void registerDefaultElgato(DartPluginRegistry registry) {
  registry.register(createElgatoPlugin(ElgatoTransport(_unconfiguredElgato)));
}

Future<RuntimeMap> _unconfiguredElgato(
  String method,
  String path,
  dynamic body,
) =>
    Future<RuntimeMap>.error(StateError('Elgato transport is not configured.'));
