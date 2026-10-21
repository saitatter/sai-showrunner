import 'dart:async';
import 'dart:io';
import '../../persistence/viewer_data_repository.dart';
import '../../services/plugin_event_hub.dart';
import '../../services/showrunner_data_service.dart';
import '../http/manifest.dart';
import '../registry/plugin_registry.dart';
import '../sound/output.dart';
import 'manifest.dart';
import 'overlay_presence.dart';
import 'websocket_bridge.dart';

Future<void> registerConfiguredOverlays(
  DartPluginRegistry registry, {
  required ShowRunnerDataService dataService,
  required DartPluginEventHub? eventHub,
  required ViewerDataRepository variablesRepository,
  required DartHttpEndpointService httpEndpointService,
  required SoundOutputRegistry configuredSoundOutputs,
  required void Function(OverlayPresenceReader reader)?
  onOverlayPresenceReaderCreated,
}) async {
  final overlayRepository = dataService.storage.resource(
    const ResourceTypeId('Overlay'),
  );
  final overlayStore = OverlayResourceStore(
    load: overlayRepository.load,
    save: overlayRepository.save,
  );
  final overlayBridge = eventHub == null
      ? null
      : DartOverlayWebSocketService(
          server: httpEndpointService,
          eventHub: eventHub,
          overlayStore: overlayStore,
          registry: registry,
          viewerDataRepository: variablesRepository,
          soundOutputs: configuredSoundOutputs,
          mediaRoot: Directory('${dataService.userDirectory.path}/media'),
          ttsRoot: Directory('${Directory.systemTemp.path}/ShowRunner-tts'),
        );
  if (overlayBridge != null) {
    onOverlayPresenceReaderCreated?.call(overlayBridge);
    for (final resource in await overlayRepository.list()) {
      overlayBridge.registerAudioOutput(resource.id);
    }
  }
  registry.register(
    createOverlaysPlugin(eventHub: eventHub, overlayStore: overlayStore),
    onStop: overlayBridge?.dispose,
  );
}

void registerDefaultOverlays(
  DartPluginRegistry registry, {
  required DartPluginEventHub? eventHub,
}) {
  registry.register(createOverlaysPlugin(eventHub: eventHub));
}
