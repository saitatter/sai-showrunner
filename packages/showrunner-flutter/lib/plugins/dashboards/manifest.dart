import '../registry/plugin_contract.dart';

const dashboardPlugin = DartPluginManifest(
  id: 'dashboards',
  name: 'Dashboards',
);

DartPluginManifest createDashboardPlugin() =>
    DartPluginManifest(id: 'dashboards', name: 'Dashboards');
