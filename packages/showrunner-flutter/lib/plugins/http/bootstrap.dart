import 'dart:io';
import '../../services/plugin_event_hub.dart';
import '../registry/plugin_factory_settings.dart';
import '../registry/plugin_registry.dart';
import 'manifest.dart';

DartHttpEndpointService createPluginHttpEndpoint({
  required Map<String, dynamic> settings,
  int? portOverride,
}) => DartHttpEndpointService(
  host: portOverride == null && settings['allowRemoteAccess'] == true
      ? InternetAddress.anyIPv4.address
      : InternetAddress.loopbackIPv4.address,
  port: portOverride ?? pluginPort(settings['port'], 8181),
);

void registerConfiguredHttp(
  DartPluginRegistry registry, {
  required DartPluginEventHub? eventHub,
  required DartHttpEndpointService httpEndpointService,
}) {
  registry.register(
    createHttpPlugin(eventHub: eventHub, endpointService: httpEndpointService),
    onStart: httpEndpointService.start,
    onStop: httpEndpointService.stop,
  );
}

void registerDefaultHttp(
  DartPluginRegistry registry, {
  required DartPluginEventHub? eventHub,
}) {
  registry.register(createHttpPlugin(eventHub: eventHub));
}
