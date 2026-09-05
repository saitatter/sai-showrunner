import 'dart:io';

import '../../persistence/resource_repository.dart';
import '../../schema/resource.dart';
import '../../runtime/expression.dart';
import '../../services/plugin_event_hub.dart';
import '../../services/showrunner_data_service.dart';
import 'actions.dart';
import 'transport.dart';

final class ObsConnectionEndpoint {
  const ObsConnectionEndpoint({
    required this.id,
    required this.host,
    required this.port,
    this.password,
  });

  final String id;
  final String host;
  final int port;
  final String? password;

  String get cacheKey => '$id|$host|$port|${password ?? ''}';
}

typedef ObsTransportFactory =
    ObsTransport Function(
      ObsConnectionEndpoint endpoint,
      void Function(String state, dynamic value)? onStateChanged,
    );

/// Resolves the configured default OBS resource for every request.
///
/// The reference product models OBS connections as resources and exposes one
/// selected default to actions and state providers. Keeping that resolution
/// here lets all OBS-backed plugins share one lifecycle without putting file
/// access in action definitions or widgets.
final class ObsConnectionRouter implements ObsTransport {
  ObsConnectionRouter({
    required this.dataService,
    this.eventHub,
    this.onStateChanged,
    this.settingsLoader,
    this.resourceLoader,
    ObsTransportFactory? transportFactory,
  }) : _transportFactory =
           transportFactory ??
           ((endpoint, onStateChanged) => ObsWebSocketTransport(
             host: endpoint.host,
             port: endpoint.port,
             password: endpoint.password,
             eventHub: eventHub,
             onStateChanged: onStateChanged,
           ));

  final ShowRunnerDataService dataService;
  final DartPluginEventHub? eventHub;
  final void Function(String state, dynamic value)? onStateChanged;
  final Future<Map<String, dynamic>> Function()? settingsLoader;
  final Future<List<ResourceData>> Function()? resourceLoader;
  final ObsTransportFactory _transportFactory;
  final _transports = <String, ObsTransport>{};

  @override
  Future<RuntimeMap> call(String request, RuntimeMap data) async {
    final endpoint = await resolveEndpoint();
    final transport = _transports.putIfAbsent(
      endpoint.cacheKey,
      () => _transportFactory(endpoint, onStateChanged),
    );
    return transport.call(request, data);
  }

  Future<ObsConnectionEndpoint> resolveEndpoint() async {
    final settings =
        await (settingsLoader?.call() ?? dataService.loadPluginSettings('obs'));
    final resources =
        await (resourceLoader?.call() ??
            ResourceRepository(
              Directory('${dataService.userDirectory.path}/obs/connections'),
            ).list());
    final selectedId = settings['obsDefault']?.toString();
    final selected = resources
        .where((resource) => resource.id == selectedId)
        .firstOrNull;
    final fallback =
        selected ??
        (selectedId == null && resources.length == 1 ? resources.first : null);
    final config = fallback?.config;
    final host = config?['host']?.toString() ?? settings['host']?.toString();
    final port = _port(config?['port'] ?? settings['port']);
    if (host == null || host.trim().isEmpty || port == null) {
      throw StateError('OBS connection is not configured.');
    }
    return ObsConnectionEndpoint(
      id: fallback?.id ?? 'settings',
      host: host.trim(),
      port: port,
      password:
          config?['password']?.toString() ?? settings['password']?.toString(),
    );
  }

  @override
  Future<void> close() async {
    final transports = _transports.values.toList();
    _transports.clear();
    await Future.wait(transports.map((transport) => transport.close()));
  }
}

int? _port(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value');
