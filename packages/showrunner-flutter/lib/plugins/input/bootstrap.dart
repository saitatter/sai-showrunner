import 'dart:io';
import '../registry/plugin_registry.dart';
import 'manifest.dart';
import 'native_input.dart';

void registerConfiguredInput(
  DartPluginRegistry registry, {
  InputPlatform? platform,
  bool? nativeHooksSupported,
}) {
  final inputPlatform = platform ?? const NativeInputPlatform();
  final supported = nativeHooksSupported ?? Platform.isWindows;
  var eventsStarted = false;
  registry.register(
    createInputPlugin(platform: inputPlatform),
    initialHealth: supported
        ? const DartPluginHealth.ready()
        : const DartPluginHealth(
            status: DartPluginHealthStatus.unavailable,
            message:
                'Global input hooks and input simulation are currently Windows-only.',
          ),
    onStart: supported
        ? () async {
            eventsStarted = true;
            await inputPlatform.startEvents();
          }
        : null,
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
