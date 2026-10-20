import '../registry/plugin_registry.dart';
import 'manifest.dart';
import 'native_input.dart';

void registerConfiguredInput(DartPluginRegistry registry) {
  final inputPlatform = const NativeInputPlatform();
  var eventsStarted = false;
  registry.register(
    createInputPlugin(platform: inputPlatform),
    onStart: () async {
      eventsStarted = true;
      await inputPlatform.startEvents();
    },
    onStop: () async {
      if (eventsStarted) {
        eventsStarted = false;
        await inputPlatform.stopEvents();
      }
    },
  );
}

void registerDefaultInput(DartPluginRegistry registry) {
  registry.register(createInputPlugin());
}
