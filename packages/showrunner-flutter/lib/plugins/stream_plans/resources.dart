import 'resource_codec.dart';
import '../../schema/stream_plan.dart';
import '../registry/plugin_contract.dart';

final _streamPlanResource = ResourceSpec(
  ownerId: const PluginId('stream-plans'),
  resourceTypeId: const ResourceTypeId('StreamPlan'),
  displayName: 'Stream Plan',
  storageDirectory: 'stream-plans',
  configurationCodec: const StreamPlanConfigurationCodec(),
  defaultConfigFactory: (name) => {
    'name': name,
    'activationAutomation': emptyInlineAutomation(),
    'deactivationAutomation': emptyInlineAutomation(),
    'segments': <Map<String, dynamic>>[],
  },
);

final List<DartResourceContract> streamPlansResourceContracts =
    List.unmodifiable([_streamPlanResource]);
