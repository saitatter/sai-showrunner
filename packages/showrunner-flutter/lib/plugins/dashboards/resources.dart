import 'resource_codec.dart';
import '../registry/plugin_contract.dart';

final _dashboardResource = ResourceSpec(
  ownerId: const PluginId('dashboards'),
  resourceTypeId: const ResourceTypeId('Dashboard'),
  displayName: 'Dashboard',
  storageDirectory: 'dashboards',
  configurationCodec: const DashboardConfigurationCodec(),
  defaultConfigFactory: (name) => {
    'name': name,
    'pages': <Map<String, dynamic>>[],
    'remoteTwitchIds': <String>[],
    'resourceSlots': <Map<String, dynamic>>[],
  },
);

final List<DartResourceContract> dashboardsResourceContracts =
    List.unmodifiable([_dashboardResource]);
