import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/showrunner_data_service.dart';
import '../../runtime/expression.dart';
import '../../plugins/registry/plugin_registry.dart';
import '../../plugins/remote/satellite.dart';
import 'remote_dashboard_view.dart';

typedef RemoteDashboardFetcher =
    Future<List<RemoteDashboardInfo>> Function(String accessToken);

final class RemoteDashboardInfo {
  const RemoteDashboardInfo({
    required this.ownerId,
    required this.dashboardId,
    required this.name,
  });

  final String ownerId;
  final String dashboardId;
  final String name;

  factory RemoteDashboardInfo.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Remote dashboard must be an object.');
    }
    final json = Map<String, dynamic>.from(value);
    final ownerId = json['ownerId']?.toString().trim() ?? '';
    final dashboardId = json['dashboardId']?.toString().trim() ?? '';
    final name = json['dashboardName']?.toString().trim() ?? '';
    if (ownerId.isEmpty || dashboardId.isEmpty || name.isEmpty) {
      throw const FormatException('Remote dashboard has incomplete identity.');
    }
    return RemoteDashboardInfo(
      ownerId: ownerId,
      dashboardId: dashboardId,
      name: name,
    );
  }
}

final class RemoteDashboardService {
  RemoteDashboardService({required this.dataService, this.fetcher});

  final ShowRunnerDataService dataService;
  final RemoteDashboardFetcher? fetcher;

  Future<List<RemoteDashboardInfo>> listAvailable() async {
    final settings = await dataService.loadPluginSettings('twitch');
    final token = settings['accessToken']?.toString().trim() ?? '';
    if (token.isEmpty) {
      throw StateError(
        'Twitch access token is required to discover remote dashboards.',
      );
    }
    return (fetcher ?? _fetchFromCloud)(token);
  }

  Future<List<RemoteDashboardInfo>> _fetchFromCloud(String token) async {
    final remoteSettings = await dataService.loadPluginSettings('remote');
    final configured = remoteSettings['apiBase']?.toString().trim() ?? '';
    final base = configured.isEmpty ? 'https://api.ShowRunner.io' : configured;
    final client = HttpClient();
    try {
      final request = await client.getUrl(
        Uri.parse('$base/api/dashboard-access/remote'),
      );
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Remote dashboard discovery failed (${response.statusCode}): $text',
        );
      }
      final decoded = text.isEmpty ? const <dynamic>[] : jsonDecode(text);
      if (decoded is! List) {
        throw const FormatException(
          'Remote dashboard discovery must return a list.',
        );
      }
      final dashboards = <RemoteDashboardInfo>[];
      for (final item in decoded) {
        try {
          dashboards.add(RemoteDashboardInfo.fromJson(item));
        } on FormatException {
          // One malformed dashboard must not hide all valid dashboard entries.
        }
      }
      return dashboards;
    } finally {
      client.close(force: true);
    }
  }
}

class RemoteWorkspace extends StatefulWidget {
  const RemoteWorkspace({
    super.key,
    required this.dataService,
    this.connectionManager,
    this.registryFuture,
  });

  final ShowRunnerDataService dataService;
  final RemoteSatelliteConnectionManager? connectionManager;
  final Future<DartPluginRegistry>? registryFuture;

  @override
  State<RemoteWorkspace> createState() => _RemoteWorkspaceState();
}

class _RemoteWorkspaceState extends State<RemoteWorkspace> {
  late final RemoteDashboardService _service;
  late final RemoteSatelliteConnectionManager _connectionManager;
  late final bool _ownsConnectionManager;
  Future<List<RemoteDashboardInfo>>? _dashboardsFuture;
  Object? _lastError;

  @override
  void initState() {
    super.initState();
    _service = RemoteDashboardService(dataService: widget.dataService);
    _ownsConnectionManager = widget.connectionManager == null;
    _connectionManager =
        widget.connectionManager ??
        RemoteSatelliteConnectionManager(
          dataService: widget.dataService,
          resourceRpc: widget.registryFuture == null
              ? null
              : _invokeLocalResource,
        );
    _connectionManager.addListener(_connectionChanged);
    _refresh();
  }

  @override
  void dispose() {
    _connectionManager.removeListener(_connectionChanged);
    if (_ownsConnectionManager) _connectionManager.dispose();
    super.dispose();
  }

  void _connectionChanged() {
    if (mounted) setState(() {});
  }

  void _refresh() {
    _lastError = null;
    _dashboardsFuture = _service.listAvailable().catchError((error) {
      if (mounted) setState(() => _lastError = error);
      return <RemoteDashboardInfo>[];
    });
    if (mounted) setState(() {});
  }

  Future<void> _connect(RemoteDashboardInfo dashboard) async {
    final settings = await widget.dataService.loadPluginSettings('twitch');
    final satelliteId = settings['broadcasterId']?.toString().trim() ?? '';
    if (satelliteId.isEmpty) {
      if (mounted) {
        setState(
          () => _lastError = StateError(
            'Twitch broadcaster ID is required before connecting to a dashboard.',
          ),
        );
      }
      return;
    }
    try {
      setState(() => _lastError = null);
      await _connectionManager.connect(
        SatelliteConnectionConfig(
          satelliteService: 'twitch',
          satelliteId: satelliteId,
          showRunnerService: 'twitch',
          showRunnerId: dashboard.ownerId,
          dashboardId: dashboard.dashboardId,
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _lastError = error);
    }
  }

  Future<void> _disconnect() => _connectionManager.disconnect();

  Future<Object?> _invokeLocalResource(
    RemoteResourceSlot slot,
    String method,
    List<dynamic> args,
  ) async {
    final resourceId = slot.resourceId;
    if (resourceId == null || resourceId.isEmpty) {
      throw StateError('Remote resource slot is not bound in Flutter.');
    }
    final registry = await widget.registryFuture!;
    dynamic argument(int index) => index < args.length ? args[index] : null;
    final context = EvaluationContext();
    switch ('${slot.resourceType}:$method') {
      case 'Light:setLightState':
        return registry.invokeAction('iot', 'light', {
          'light': resourceId,
          'on': argument(1) ?? true,
          'lightColor': argument(0),
          'transition': argument(2) ?? 0.5,
        }, context: context);
      case 'Plug:setPlugState':
        return registry.invokeAction('iot', 'plug', {
          'plug': resourceId,
          'switch': argument(0) ?? true,
        }, context: context);
      case 'SoundOutput:playFile':
        if (argument(1)?.toString().trim().isEmpty != false) {
          throw StateError('Remote sound request did not include a file path.');
        }
        return registry.invokeAction('sound', 'sound', {
          'output': resourceId,
          'sound': argument(1),
          'startTime': argument(2) ?? 0,
          'endTime': argument(3),
          'volume': argument(4) ?? 100,
        }, context: context);
      case 'SoundOutput:abortPlay':
        return null;
      default:
        throw UnsupportedError(
          'Flutter has no local remote-resource handler for ${slot.resourceType}.$method.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final connection = _connectionManager.connection;
    if (connection != null &&
        connection.state != SatelliteConnectionState.disconnected) {
      return RemoteDashboardView(
        connection: connection,
        dataService: widget.dataService,
        onDisconnect: _disconnect,
      );
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Remote workspace',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            OutlinedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Discover dashboards shared with the authenticated Twitch account.',
        ),
        const SizedBox(height: 20),
        Card(
          child: ListTile(
            leading: const Icon(Icons.cloud_queue, color: Colors.blue),
            title: const Text('Flutter remote dashboard connection'),
            subtitle: const Text(
              'Connect over WebRTC DataChannel, receive live dashboard configuration '
              'and state updates, and bind local resources to remote slots.',
            ),
          ),
        ),
        if (_lastError != null)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('Remote dashboard discovery failed'),
              subtitle: Text('$_lastError'),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          'Available dashboards',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        FutureBuilder<List<RemoteDashboardInfo>>(
          future: _dashboardsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final dashboards = snapshot.data ?? const <RemoteDashboardInfo>[];
            if (dashboards.isEmpty) {
              return const ListTile(
                leading: Icon(Icons.dashboard_outlined),
                title: Text('No remote dashboards available'),
                subtitle: Text(
                  'Authenticate Twitch or ask another broadcaster to share a dashboard.',
                ),
              );
            }
            return Column(
              children: [
                for (final dashboard in dashboards)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.dashboard),
                      title: Text(dashboard.name),
                      subtitle: Text(
                        'Owner ${dashboard.ownerId} · Dashboard ${dashboard.dashboardId}',
                      ),
                      trailing: FilledButton.icon(
                        onPressed: () => _connect(dashboard),
                        icon: const Icon(Icons.link),
                        label: const Text('Connect'),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
