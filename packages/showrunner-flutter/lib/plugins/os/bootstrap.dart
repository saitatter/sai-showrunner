import '../registry/plugin_registry.dart';
import 'manifest.dart';

void registerDefaultOs(DartPluginRegistry registry) {
  registry.register(createOsPlugin());
}
