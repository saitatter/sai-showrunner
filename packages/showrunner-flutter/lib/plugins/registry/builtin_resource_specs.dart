import 'plugin_contract.dart';
import '../overlays/resources.dart';
import '../stream_plans/resources.dart';
import '../variables/resources.dart';
import '../obs/resources.dart';
import '../minecraft/resources.dart';
import '../sound/resources.dart';
import '../twitch/resources.dart';
import '../discord/resources.dart';
import '../bluesky/resources.dart';
import '../dashboards/resources.dart';
import '../spellcast/resources.dart';
import '../iot/resources.dart';
import '../input/resources.dart';
import '../wyze/resources.dart';

final Map<String, DartResourceContract> _resourceIndex =
    _indexResourceContracts([
      ...overlaysResourceContracts,
      ...streamPlansResourceContracts,
      ...variablesResourceContracts,
      ...obsResourceContracts,
      ...minecraftResourceContracts,
      ...soundResourceContracts,
      ...twitchResourceContracts,
      ...discordResourceContracts,
      ...blueskyResourceContracts,
      ...dashboardsResourceContracts,
      ...spellcastResourceContracts,
      ...iotResourceContracts,
      ...inputResourceContracts,
      ...wyzeResourceContracts,
    ]);

Map<String, DartResourceContract> _indexResourceContracts(
  List<DartResourceContract> resources,
) {
  final index = <String, DartResourceContract>{};
  for (final resource in resources) {
    final id = resource.resourceTypeId.value;
    if (index.containsKey(id)) {
      throw StateError('Duplicate canonical resource type: $id');
    }
    index[id] = resource;
  }
  return Map.unmodifiable(index);
}

/// Flutter-only editor assembly resolves the same provider-owned declarations
/// that manifests expose to graph contracts. Unknown resource types fail visibly.
DartResourceContract builtInResourceSpec(String resourceType) =>
    _resourceIndex[resourceType] ??
    (throw ArgumentError.value(
      resourceType,
      'resourceType',
      'Unknown built-in resource type.',
    ));

/// Canonical provider-owned resource declarations for storage/UI composition.
Iterable<DartResourceContract> get builtInResourceSpecs =>
    _resourceIndex.values;
