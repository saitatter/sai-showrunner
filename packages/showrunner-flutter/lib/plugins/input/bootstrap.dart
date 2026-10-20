import '../registry/plugin_registry.dart';
import 'manifest.dart';
import 'native_input.dart';

void registerConfiguredInput(DartPluginRegistry registry) {
  final inputPlatform = const NativeInputPlatform();
  registry.register(
    createInputPlugin(platform: inputPlatform),
    onStart: inputPlatform.startEvents,
    onStop: inputPlatform.stopEvents,
  );
}

void registerDefaultInput(DartPluginRegistry registry) {
  registry.register(createInputPlugin());
}
