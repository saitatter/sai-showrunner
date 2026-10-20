import 'dart:async';
import '../../runtime/expression.dart';
import '../registry/plugin_registry.dart';
import 'manifest.dart';

void registerConfiguredTwinkly(DartPluginRegistry registry) {
  final twinklyTransport = TwinklyHttpTransport();
  registry.register(
    createTwinklyPlugin(TwinklyTransport(twinklyTransport.request)),

    initialHealth: const DartPluginHealth.connectionUnchecked(),
  );
}

void registerDefaultTwinkly(DartPluginRegistry registry) {
  registry.register(
    createTwinklyPlugin(TwinklyTransport(_unconfiguredTwinkly)),

    initialHealth: const DartPluginHealth.notConfigured(),
  );
}

Future<RuntimeMap> _unconfiguredTwinkly(
  String ip,
  String method,
  String path,
  RuntimeMap query,
  dynamic body,
) => Future<RuntimeMap>.error(
  StateError('Twinkly transport is not configured.'),
);
