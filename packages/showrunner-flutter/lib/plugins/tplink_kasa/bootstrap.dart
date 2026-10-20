import 'dart:async';
import '../../runtime/expression.dart';
import '../../services/showrunner_data_service.dart';
import '../registry/plugin_factory_settings.dart';
import '../registry/plugin_registry.dart';
import 'manifest.dart';

Future<void> registerConfiguredKasa(
  DartPluginRegistry registry, {
  required ShowRunnerDataService dataService,
}) async {
  final kasaSettings = await dataService.loadPluginSettings('tplink-kasa');
  final kasaHost = kasaSettings['host']?.toString().trim();
  final kasaTransport = kasaHost?.isNotEmpty == true
      ? KasaTcpTransport(
          host: kasaHost!,
          port: pluginPort(kasaSettings['port'], 9999),
        )
      : null;
  final configuredKasaTransport = KasaTransport(
    kasaTransport?.request ?? _unconfiguredKasa,
  );
  registry.register(
    createKasaPlugin(
      configuredKasaTransport,
      transportResolver: (config) {
        final host = config['host']?.toString().trim() ?? '';
        if (host.isEmpty) return configuredKasaTransport;
        return KasaTransport(
          KasaTcpTransport(
            host: host,
            port: pluginPort(config['port'], 9999),
          ).request,
        );
      },
    ),
  );
}

void registerDefaultKasa(DartPluginRegistry registry) {
  registry.register(createKasaPlugin(KasaTransport(_unconfiguredKasa)));
}

Future<RuntimeMap> _unconfiguredKasa(RuntimeMap request) =>
    Future<RuntimeMap>.error(
      StateError('TP-Link Kasa transport is not configured.'),
    );
