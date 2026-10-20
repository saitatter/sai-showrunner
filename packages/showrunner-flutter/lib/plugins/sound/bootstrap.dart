import 'dart:async';
import 'dart:io';
import '../../persistence/resource_repository.dart';
import '../../services/showrunner_data_service.dart';
import '../registry/plugin_factory_settings.dart';
import '../registry/plugin_registry.dart';
import 'manifest.dart';
import 'output.dart';
import 'tts_runtime.dart';
import 'windows_audio.dart';

Future<SoundOutputRegistry> registerConfiguredSound(
  DartPluginRegistry registry, {
  required ShowRunnerDataService dataService,
  required TtsSpeechService? ttsService,
  required SoundOutputRegistry? soundOutputs,
}) async {
  final soundSettings = await dataService.loadPluginSettings('sound');
  final defaultOutput = soundSettings['defaultOutput']?.toString().trim();
  final splitterDirectory = Directory(
    '${dataService.userDirectory.path}/sound/splitters',
  );
  late final SoundOutputRegistry configuredSoundOutputs;
  Future<void> refreshSoundSplitters() async {
    final splitters = await ResourceRepository(splitterDirectory).list();
    for (final splitter in splitters) {
      configuredSoundOutputs.registerSplitterConfig(
        splitter.id,
        splitter.config,
      );
    }
  }

  configuredSoundOutputs =
      soundOutputs ??
      createDefaultSoundOutputRegistry(
        defaultOutputId: defaultOutput,
        refresh: refreshSoundSplitters,
      );
  if (soundOutputs != null && defaultOutput?.isNotEmpty == true) {
    configuredSoundOutputs.defaultOutputId = defaultOutput;
  }
  if (soundOutputs == null) {
    await refreshSoundSplitters();
  }
  registry.register(
    createSoundPlugin(
      ttsService: ttsService,
      soundOutputs: configuredSoundOutputs,
      ttsVoiceResolver: (id) async {
        final resource = await ResourceRepository(
          Directory('${dataService.userDirectory.path}/sound/tts'),
        ).load(id);
        return resource?.config;
      },
      globalVolume: pluginPercentage(soundSettings['globalVolume'], 100),
    ),
  );
  return configuredSoundOutputs;
}

void registerDefaultSound(
  DartPluginRegistry registry, {
  required TtsSpeechService? ttsService,
  required SoundOutputRegistry? soundOutputs,
}) {
  registry.register(
    createSoundPlugin(ttsService: ttsService, soundOutputs: soundOutputs),
  );
}
