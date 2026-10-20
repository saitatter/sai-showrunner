import '../registry/plugin_contract.dart';
import 'resources.dart';

final dashboardPlugin = DartPluginManifest(
  id: PluginId('dashboards'),
  name: 'Dashboards',
  resources: dashboardsResourceContracts,
);

DartPluginManifest createDashboardPlugin() => dashboardPlugin;
