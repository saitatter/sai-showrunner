import '../../services/plugin_event_hub.dart';
import '../registry/plugin_registry.dart';
import 'manifest.dart';

void registerDefaultRandom(
  DartPluginRegistry registry, {
  required DartPluginEventHub? eventHub,
}) {
  registry.register(createRandomPlugin(eventHub: eventHub));
}
