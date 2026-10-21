import '../../plugins/sound/windows_audio.dart';
import '../../services/showrunner_data_service.dart';
import '../../plugins/registry/builtin_resource_specs.dart';
import '../../schema/identifiers.dart';

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
  if (resourceType == 'Profile') {
    return (await dataService.listUserFiles('profiles'))
        .where((fileName) => fileName.endsWith('.yaml'))
        .map((fileName) => fileName.substring(0, fileName.length - 5))
        .toList(growable: false);
  }
  if (resourceType == 'SoundOutput') {
    final systemOutputs = createDefaultSoundOutputRegistry().outputs.map(
      (output) => output.id,
    );
    final splitters = await dataService.storage
        .resource(const ResourceTypeId('AudioSplitterOutput'))
        .list();
    return {
      'system.default',
      'system.communications',
      ...systemOutputs,
      ...splitters.map((resource) => resource.id),
    }.toList(growable: false);
  }

  if (!builtInResourceSpecs.any(
    (spec) => spec.resourceTypeId.value == resourceType,
  )) {
    return const [];
  }
  final resources = await dataService.storage
      .resource(ResourceTypeId(resourceType))
      .list();
  return resources.map((resource) => resource.id).toList(growable: false);
}
