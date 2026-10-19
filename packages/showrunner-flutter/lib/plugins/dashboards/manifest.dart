import '../registry/plugin_contract.dart';
import '../registry/builtin_resource_specs.dart';

final dashboardPlugin = DartPluginManifest(
  id: PluginId('dashboards'),
  name: 'Dashboards',
  resources: builtInResourceSpecsFor(const PluginId('dashboards')),
);

DartPluginManifest createDashboardPlugin() => dashboardPlugin;
