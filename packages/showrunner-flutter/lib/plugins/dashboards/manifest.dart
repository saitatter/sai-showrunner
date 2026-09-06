import '../registry/plugin_contract.dart';

const dashboardPlugin = DartPluginManifest(
  id: 'dashboards',
  name: 'Dashboards',
);

DartPluginManifest createDashboardPlugin({
  Future<void> Function()? start,
  Future<void> Function()? stop,
}) => DartPluginManifest(
  id: 'dashboards',
  name: 'Dashboards',
  start: start,
  stop: stop,
);
