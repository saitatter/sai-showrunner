import '../registry/plugin_registry.dart';
import '../remote/dashboard_host.dart';
import 'manifest.dart';

void registerConfiguredDashboards(
  DartPluginRegistry registry, {
  required RemoteDashboardHost? dashboardHost,
}) {
  registry.register(
    createDashboardPlugin(),
    onStart: dashboardHost?.start,
    onStop: dashboardHost?.stop,
  );
}

void registerDefaultDashboards(DartPluginRegistry registry) {
  registry.register(dashboardPlugin);
}
