import 'dart:io';

import '../../persistence/resource_repository.dart';
import '../../plugins/sound/windows_audio.dart';
import '../../services/showrunner_data_service.dart';
import 'resource_editor_registry.dart';

/// Loads IDs that can be selected by a resource-valued graph input.
///
/// Sound outputs are partly virtual: the Windows backend exposes system
/// endpoints at runtime while user-defined splitters are persisted as regular
/// resources. Keep that union in one place so the main graph and profile
/// automation editors offer the same choices.
Future<List<String>> loadResourceOptions(
  ShowRunnerDataService dataService,
  String resourceType,
) async {
  if (resourceType == 'ActionQueue') {
    return (await dataService.listUserFiles('queues'))
        .where((fileName) => fileName.endsWith('.yaml'))
        .map((fileName) => fileName.substring(0, fileName.length - 5))
        .toList(growable: false);
  }
  if (resourceType == 'Automation') {
    return (await dataService.listUserFiles('automations'))
        .where((fileName) => fileName.endsWith('.yaml'))
        .map((fileName) => fileName.substring(0, fileName.length - 5))
        .toList(growable: false);
  }
  if (resourceType == 'SoundOutput') {
    final systemOutputs = createDefaultSoundOutputRegistry().outputs.map(
      (output) => output.id,
    );
    final splitters = await ResourceRepository(
      Directory('${dataService.userDirectory.path}/sound/splitters'),
    ).list();
    return {
      'system.default',
      'system.communications',
      ...systemOutputs,
      ...splitters.map((resource) => resource.id),
    }.toList(growable: false);
  }

  final definition = createDefaultResourceEditorRegistry().find(resourceType);
  if (definition == null) return const [];
  final resources = await ResourceRepository(
    Directory(
      '${dataService.userDirectory.path}/${definition.storageDirectory}',
    ),
  ).list();
  return resources.map((resource) => resource.id).toList(growable: false);
}
