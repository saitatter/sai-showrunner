import 'dart:async';
import 'dart:io';
import '../../graph/definitions/showrunner_graph_types.dart';
import '../../graph/domain/automation_document.dart';
import '../../persistence/profile_repository.dart';
import '../../services/plugin_event_hub.dart';
import '../../services/showrunner_data_service.dart';
import '../registry/plugin_factory_settings.dart';
import '../registry/plugin_registry.dart';
import 'dashboard_host.dart';
import 'manifest.dart';
import 'satellite.dart';

RemoteDashboardHost? createPluginDashboardHost({
  required ShowRunnerDataService dataService,
  required DartPluginRegistry registry,
  required DartPluginEventHub? eventHub,
}) => eventHub == null
    ? null
    : RemoteDashboardHost(
        dataService: dataService,
        registry: registry,
        eventHub: eventHub,
        signaling: SatelliteSignalingController(dataService: dataService),
      );

Future<void> registerConfiguredRemote(
  DartPluginRegistry registry, {
  required ShowRunnerDataService dataService,
  required DartPluginEventHub? eventHub,
}) async {
  final remoteSettings = await dataService.loadPluginSettings('remote');
  final remoteEnabled = remoteSettings['enabled'] == true;
  final remoteHost = remoteSettings['host']?.toString().trim();
  final remotePort = pluginPort(remoteSettings['port'], 8390);
  final remoteRuntime = remoteEnabled && eventHub != null
      ? RemoteButtonRuntime(
          eventHub: eventHub,
          host: remoteHost?.isNotEmpty == true ? remoteHost! : '127.0.0.1',
          port: remotePort,
          loadButtonNames: () => _loadRemoteButtonNames(dataService),
          onStateChanged: (state) =>
              registry.updateState('remote', 'server', state),
        )
      : null;
  registry.register(
    createRemotePlugin(eventHub: eventHub, runtime: remoteRuntime),
    onStart: remoteRuntime?.start,
    onStop: remoteRuntime?.stop,

    initialHealth: (remoteRuntime != null)
        ? const DartPluginHealth.connectionUnchecked()
        : const DartPluginHealth.notConfigured(),
  );
}

void registerDefaultRemote(
  DartPluginRegistry registry, {
  required DartPluginEventHub? eventHub,
}) {
  registry.register(
    createRemotePlugin(eventHub: eventHub),
    initialHealth: const DartPluginHealth.notConfigured(),
  );
}

Future<List<String>> _loadRemoteButtonNames(
  ShowRunnerDataService dataService,
) async {
  final names = <String>{};
  for (final fileName in await dataService.listUserFiles('profiles')) {
    try {
      final profile = await ProfileRepository(
        File('${dataService.userDirectory.path}/profiles/$fileName'),
      ).load();
      if (profile == null) continue;
      for (final trigger in profile.triggers) {
        final automation = AutomationDocument.fromJson(
          Map<String, Object?>.from(trigger['automation'] as Map),
        );
        for (final node
            in automation.graph.spaces[mainAutomationSpace]!.nodes.values) {
          if (decodeContractNodeType(node.type, 'trigger') case (
            'remote',
            'button',
          )) {
            final config = node.data['config'];
            final name = config is Map
                ? config['name']?.toString().trim()
                : null;
            if (name != null && name.isNotEmpty) names.add(name);
          }
        }
      }
    } on Object {
      // A malformed profile should not make the remote button API unavailable.
    }
  }
  return names.toList(growable: false);
}
