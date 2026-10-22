import 'package:flutter/material.dart';

import '../../services/showrunner_data_service.dart';
import '../../runtime/expression.dart';
import '../../plugins/registry/plugin_registry.dart';
import '../../plugins/remote/satellite.dart';
import '../../plugins/twitch/account_runtime.dart';
import 'remote_dashboard_view.dart';
import 'remote_dashboard_service.dart';
import '../../design_system/workspace_notice.dart';
export 'remote_dashboard_service.dart';

class RemoteWorkspace extends StatefulWidget {
  const RemoteWorkspace({
    super.key,
    required this.dataService,
    this.connectionManager,
    this.registryFuture,
    this.discoverDashboards,
  });

  final Future<List<RemoteDashboardInfo>> Function()? discoverDashboards;
  final ShowRunnerDataService dataService;
  final RemoteSatelliteConnectionManager? connectionManager;
  final Future<DartPluginRegistry>? registryFuture;

  @override
  State<RemoteWorkspace> createState() => _RemoteWorkspaceState();
}

class _RemoteWorkspaceState extends State<RemoteWorkspace> {
  late RemoteDashboardService _service;
  late RemoteSatelliteConnectionManager _connectionManager;
  late bool _ownsConnectionManager;
  Future<List<RemoteDashboardInfo>>? _dashboardsFuture;
  Object? _lastError;
  Object _owner = Object();
  bool _connecting = false;

  bool _isCurrent(Object owner) => mounted && identical(owner, _owner);

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  void _initialize() {
    _owner = Object();
    _connecting = false;
    _lastError = null;
    _service = RemoteDashboardService(dataService: widget.dataService);
    final owner = _owner;
    final registryFuture = widget.registryFuture;
    _ownsConnectionManager = widget.connectionManager == null;
    _connectionManager =
        widget.connectionManager ??
        RemoteSatelliteConnectionManager(
          dataService: widget.dataService,
          resourceRpc: registryFuture == null
              ? null
              : (slot, method, args) => _invokeLocalResource(
                  owner,
                  registryFuture,
                  slot,
                  method,
                  args,
                ),
        );
    _connectionManager.addListener(_connectionChanged);
    _refresh();
  }

  @override
  void didUpdateWidget(covariant RemoteWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.dataService, widget.dataService) ||
        oldWidget.connectionManager != widget.connectionManager ||
        oldWidget.registryFuture != widget.registryFuture ||
        oldWidget.discoverDashboards != widget.discoverDashboards) {
      _connectionManager.removeListener(_connectionChanged);
      if (_ownsConnectionManager) _connectionManager.dispose();
      _initialize();
    }
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
    _dashboardsFuture = (widget.discoverDashboards ?? _service.listAvailable)();
    if (mounted) setState(() {});
  }

  Future<void> _connect(RemoteDashboardInfo dashboard) async {
    if (_connecting) return;
    final owner = _owner;
    final data = widget.dataService;
    final manager = _connectionManager;
    setState(() {
      _connecting = true;
      _lastError = null;
    });
    try {
      final settings = await loadTwitchChannelSettings(data);
      if (!_isCurrent(owner)) return;
      final satelliteId = settings['broadcasterId']?.toString().trim() ?? '';
      if (satelliteId.isEmpty) {
        throw StateError('Twitch identity is unavailable.');
      }
      await manager.connect(
        SatelliteConnectionConfig(
          satelliteService: 'twitch',
          satelliteId: satelliteId,
          showRunnerService: 'twitch',
          showRunnerId: dashboard.ownerId,
          dashboardId: dashboard.dashboardId,
        ),
      );
    } catch (error) {
      if (_isCurrent(owner)) setState(() => _lastError = error);
    } finally {
      if (_isCurrent(owner)) setState(() => _connecting = false);
    }
  }

  Future<void> _disconnect() => _connectionManager.disconnect();

  Future<Object?> _invokeLocalResource(
    Object owner,
    Future<DartPluginRegistry> registryFuture,
    RemoteResourceSlot slot,
    String method,
    List<dynamic> args,
  ) async {
    final resourceId = slot.resourceId;
    if (resourceId == null || resourceId.isEmpty) {
      throw StateError('Remote resource slot is not bound in Flutter.');
    }
    if (!_isCurrent(owner)) {
      throw StateError('Remote workspace is no longer current.');
    }
    final registry = await registryFuture;
    if (!_isCurrent(owner)) {
      throw StateError('Remote workspace is no longer current.');
    }
    dynamic argument(int index) => index < args.length ? args[index] : null;
    final context = EvaluationContext();
    switch ('${slot.resourceType}:$method') {
      case 'Light:setLightState':
        return registry.invokeActionKey(
          const ActionKey(plugin: PluginId('iot'), action: ActionId('light')),
          {
            'light': resourceId,
            'on': argument(1) ?? true,
            'lightColor': argument(0),
            'transition': argument(2) ?? 0.5,
          },
          context: context,
        );
      case 'Plug:setPlugState':
        return registry.invokeActionKey(
          const ActionKey(plugin: PluginId('iot'), action: ActionId('plug')),
          {'plug': resourceId, 'switch': argument(0) ?? true},
          context: context,
        );
      case 'SoundOutput:playFile':
        if (argument(1)?.toString().trim().isEmpty != false) {
          throw StateError('Remote sound request did not include a file path.');
        }
        return registry.invokeActionKey(
          const ActionKey(plugin: PluginId('sound'), action: ActionId('sound')),
          {
            'output': resourceId,
            '_playId': argument(0),
            'sound': argument(1),
            'startTime': argument(2) ?? 0,
            'endTime': argument(3),
            'volume': argument(4) ?? 100,
          },
          context: context,
        );
      case 'SoundOutput:abortPlay':
        final playId = argument(0)?.toString().trim() ?? '';
        if (playId.isEmpty) return {'aborted': false};
        return registry.invokeActionKey(
          const ActionKey(plugin: PluginId('sound'), action: ActionId('sound')),
          {'_abortPlay': playId},
          context: context,
        );
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
          const WorkspaceNotice(
            title: 'Remote dashboard connection failed',
            message:
                'Check Twitch authentication and the remote connection, then retry.',
            icon: Icons.error_outline,
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
            if (snapshot.hasError) {
              return WorkspaceNotice(
                title: 'Remote dashboard discovery failed',
                message:
                    'Check Twitch authentication and the remote service, then retry.',
                icon: Icons.error_outline,
                action: TextButton(
                  onPressed: _refresh,
                  child: const Text('Retry'),
                ),
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
                        onPressed: _connecting
                            ? null
                            : () => _connect(dashboard),
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
