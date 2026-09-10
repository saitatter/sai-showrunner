import '../registry/plugin_contract.dart';

const dashboardPlugin = DartPluginManifest(
  id: PluginId('dashboards'),
  name: 'Dashboards',
);

DartPluginManifest createDashboardPlugin() =>
    DartPluginManifest(id: PluginId('dashboards'), name: 'Dashboards');
