import 'dart:async';
import '../../runtime/expression.dart';
import '../../services/http_provider_transports.dart';
import '../../services/showrunner_data_service.dart';
import '../registry/plugin_registry.dart';
import 'manifest.dart';

Future<void> registerConfiguredGovee(
  DartPluginRegistry registry, {
  required ShowRunnerDataService dataService,
}) async {
  final goveeSettings = await dataService.loadPluginSettings('govee');
  final goveeApiKey = goveeSettings['apiKey'] as String?;
  final goveeTransport = goveeApiKey?.isNotEmpty == true
      ? JsonHttpTransport(
          baseUrl: 'https://developer-api.govee.com',
          headers: {'Govee-API-KEY': goveeApiKey!},
        )
      : null;
  registry.register(
    createGoveePlugin(
      GoveeTransport(goveeTransport?.request ?? _unconfiguredGovee),
    ),
  );
}

void registerDefaultGovee(DartPluginRegistry registry) {
  registry.register(createGoveePlugin(GoveeTransport(_unconfiguredGovee)));
}

Future<RuntimeMap> _unconfiguredGovee(
  String method,
  String path,
  RuntimeMap query,
  dynamic body,
) => Future<RuntimeMap>.error(StateError('Govee transport is not configured.'));
