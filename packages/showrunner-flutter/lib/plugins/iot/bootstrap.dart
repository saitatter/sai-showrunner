import '../../services/showrunner_data_service.dart';
import '../registry/plugin_registry.dart';
import 'configured_resolver.dart';
import 'manifest.dart';

void registerConfiguredIot(
  DartPluginRegistry registry, {
  required ShowRunnerDataService dataService,
}) {
  registry.register(
    createIotPlugin(
      resolver: createConfiguredIotResolver(
        registry: registry,
        dataService: dataService,
      ),
    ),

    initialHealth: const DartPluginHealth.connectionUnchecked(),
  );
}

void registerDefaultIot(DartPluginRegistry registry) {
  registry.register(
    createIotPlugin(),
    initialHealth: const DartPluginHealth.notConfigured(),
  );
}
