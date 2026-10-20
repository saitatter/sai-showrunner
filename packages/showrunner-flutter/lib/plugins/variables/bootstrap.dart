import 'dart:io';
import '../../persistence/viewer_data_repository.dart';
import '../../services/plugin_event_hub.dart';
import '../../services/showrunner_data_service.dart';
import '../registry/plugin_registry.dart';
import 'manifest.dart';
import 'runtime.dart';
import 'ui/plugin_ui.dart';

DartVariableRuntime createPluginVariableRuntime({
  required ShowRunnerDataService dataService,
  required DartPluginRegistry registry,
}) => DartVariableRuntime(
  directory: Directory('${dataService.userDirectory.path}/variables'),
  onChanged: (id, value) => registry.updateDynamicState('variables', id, value),
);

void registerConfiguredVariables(
  DartPluginRegistry registry, {
  required DartPluginEventHub? eventHub,
  required ViewerDataRepository variablesRepository,
  required DartVariableRuntime? variableRuntime,
  required DartVariableRuntime configuredVariableRuntime,
}) {
  registry.register(
    createVariablesPlugin(
      viewerDataRepository: variablesRepository,
      eventHub: eventHub,
      variableRuntime: configuredVariableRuntime,
    ),
    onStart: configuredVariableRuntime.load,
    onStop: variableRuntime == null ? configuredVariableRuntime.close : null,
  );
  registry.registerUi(
    'variables',
    createVariablesPluginUi(variableRuntime: configuredVariableRuntime),
  );
}

void registerDefaultVariables(
  DartPluginRegistry registry, {
  required DartPluginEventHub? eventHub,
  required ViewerDataRepository variablesRepository,
}) {
  registry.register(
    createVariablesPlugin(
      viewerDataRepository: variablesRepository,
      eventHub: eventHub,
    ),
  );
  registry.registerUi('variables', createVariablesPluginUi());
}
