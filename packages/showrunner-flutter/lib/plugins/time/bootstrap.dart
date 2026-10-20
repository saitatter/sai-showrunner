import '../registry/plugin_registry.dart';
import '../variables/runtime.dart';
import 'manifest.dart';

void registerDefaultTime(DartPluginRegistry registry) {
  registry.register(createTimePlugin());
}

void registerConfiguredTime(
  DartPluginRegistry registry, {
  required DartVariableRuntime configuredVariableRuntime,
}) {
  registry.register(
    createTimePlugin(variableRuntime: configuredVariableRuntime),
  );
}
