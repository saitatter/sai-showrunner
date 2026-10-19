import 'dart:io';

import '../../schema/resource.dart';
import '../../services/showrunner_data_service.dart';
import 'connection_router.dart';

final class ObsConnectionChoice {
  const ObsConnectionChoice({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.isLocal,
    this.installPath,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final bool isLocal;
  final String? installPath;
}

final class OverlayBrowserSourceStatus {
  const OverlayBrowserSourceStatus({
    required this.connected,
    this.sceneName,
    this.sourceName,
    this.expectedUrl,
    this.isCurrent = false,
  });

  final bool connected;
  final String? sceneName;
  final String? sourceName;
  final String? expectedUrl;
  final bool isCurrent;

  bool get needsCreate => connected && sourceName == null;
  bool get needsFix => connected && sourceName != null && !isCurrent;
}

abstract interface class OverlayObsSourceActions {
  Future<List<ObsConnectionChoice>> listConnections();

  Future<String?> defaultConnectionId();

  Future<String> browserSourceUrl({
    required String connectionId,
    required String overlayId,
    required int port,
  });

  Future<OverlayBrowserSourceStatus> inspect({
    required String connectionId,
    required String overlayId,
    required int width,
    required int height,
    required int port,
  });

  Future<void> createBrowserSource({
    required String connectionId,
    required String overlayId,
    required String sourceName,
    required int width,
    required int height,
    required int port,
  });

  Future<void> fixBrowserSource({
    required String connectionId,
    required String overlayId,
    required String sourceName,
    required int width,
    required int height,
    required int port,
  });

  Future<bool> openObs(String connectionId);

  Future<void> close();
}

/// Application-level OBS Browser Source operations for the overlay editor.
///
/// OBS resource loading and WebSocket calls stay outside widgets. Requests are
/// routed by the connection selected in the overlay editor, independently of
/// the global default used by graph actions.
final class OverlayObsSourceService implements OverlayObsSourceActions {
  OverlayObsSourceService({
    required this.dataService,
    ObsConnectionRouter? router,
    this.defaultConnectionLoader,
    this.localAddressLoader,
  }) : _router = router ?? ObsConnectionRouter(dataService: dataService);

  final ShowRunnerDataService dataService;
  final Future<String?> Function()? defaultConnectionLoader;
  final Future<String> Function()? localAddressLoader;
  final ObsConnectionRouter _router;

  @override
  Future<List<ObsConnectionChoice>> listConnections() async {
    final resources = await _router.listConnections();
    return resources.map(_connectionChoice).toList(growable: false);
  }

  @override
  Future<String?> defaultConnectionId() async => defaultConnectionLoader == null
      ? (await dataService.loadPluginSettings('obs'))['obsDefault']?.toString()
      : defaultConnectionLoader!();

  @override
  Future<String> browserSourceUrl({
    required String connectionId,
    required String overlayId,
    required int port,
  }) async {
    final connection = await _findConnection(connectionId);
    final host = connection.isLocal
        ? 'localhost'
        : await (localAddressLoader?.call() ?? _localNetworkAddress());
    return Uri(
      scheme: 'http',
      host: host,
      port: port,
      pathSegments: ['overlays', overlayId],
    ).toString();
  }

  @override
  Future<OverlayBrowserSourceStatus> inspect({
    required String connectionId,
    required String overlayId,
    required int width,
    required int height,
    required int port,
  }) async {
    await _router.callForConnection(connectionId, 'GetVersion', {});
    final currentScene = await _router.callForConnection(
      connectionId,
      'GetCurrentProgramScene',
      {},
    );
    final expectedUrl = await browserSourceUrl(
      connectionId: connectionId,
      overlayId: overlayId,
      port: port,
    );
    final inputList = await _router.callForConnection(
      connectionId,
      'GetInputList',
      {'inputKind': 'browser_source'},
    );
    final inputs = inputList['inputs'];
    if (inputs is! List) {
      return OverlayBrowserSourceStatus(
        connected: true,
        sceneName: currentScene['currentProgramSceneName']?.toString(),
        expectedUrl: expectedUrl,
      );
    }

    for (final input in inputs.whereType<Map>()) {
      final inputName = input['inputName']?.toString();
      if (inputName == null || inputName.isEmpty) continue;
      final settingsResponse = await _router.callForConnection(
        connectionId,
        'GetInputSettings',
        {'inputName': inputName},
      );
      final settings = settingsResponse['inputSettings'];
      if (settings is! Map || !_isOverlayUrl(settings['url'], overlayId)) {
        continue;
      }
      return OverlayBrowserSourceStatus(
        connected: true,
        sceneName: currentScene['currentProgramSceneName']?.toString(),
        sourceName: inputName,
        expectedUrl: expectedUrl,
        isCurrent:
            settings['url']?.toString() == expectedUrl &&
            _sameDimension(settings['width'], width) &&
            _sameDimension(settings['height'], height),
      );
    }

    return OverlayBrowserSourceStatus(
      connected: true,
      sceneName: currentScene['currentProgramSceneName']?.toString(),
      expectedUrl: expectedUrl,
    );
  }

  @override
  Future<void> createBrowserSource({
    required String connectionId,
    required String overlayId,
    required String sourceName,
    required int width,
    required int height,
    required int port,
  }) async {
    final name = sourceName.trim();
    if (name.isEmpty) throw ArgumentError.value(sourceName, 'sourceName');
    final current = await _router.callForConnection(
      connectionId,
      'GetCurrentProgramScene',
      {},
    );
    final sceneName = current['currentProgramSceneName']?.toString();
    if (sceneName == null || sceneName.isEmpty) {
      throw StateError('OBS has no active program scene.');
    }
    await _router.callForConnection(connectionId, 'CreateInput', {
      'sceneName': sceneName,
      'inputName': name,
      'inputKind': 'browser_source',
      'inputSettings': await _sourceSettings(
        connectionId: connectionId,
        overlayId: overlayId,
        width: width,
        height: height,
        port: port,
      ),
    });
  }

  @override
  Future<void> fixBrowserSource({
    required String connectionId,
    required String overlayId,
    required String sourceName,
    required int width,
    required int height,
    required int port,
  }) async {
    await _router.callForConnection(connectionId, 'SetInputSettings', {
      'inputName': sourceName,
      'inputSettings': await _sourceSettings(
        connectionId: connectionId,
        overlayId: overlayId,
        width: width,
        height: height,
        port: port,
      ),
      'overlay': true,
    });
  }

  @override
  Future<bool> openObs(String connectionId) async {
    if (!Platform.isWindows) return false;
    final connection = await _findConnection(connectionId);
    if (!connection.isLocal) return false;
    final path = await _obsExecutable(connection.installPath);
    if (path == null) return false;
    await Process.start(
      path,
      const <String>[],
      mode: ProcessStartMode.detached,
      workingDirectory: File(path).parent.path,
    );
    return true;
  }

  @override
  Future<void> close() => _router.close();

  Future<Map<String, dynamic>> _sourceSettings({
    required String connectionId,
    required String overlayId,
    required int width,
    required int height,
    required int port,
  }) async => {
    'url': await browserSourceUrl(
      connectionId: connectionId,
      overlayId: overlayId,
      port: port,
    ),
    'width': width,
    'height': height,
  };

  Future<ObsConnectionChoice> _findConnection(String id) async {
    final connections = await listConnections();
    return connections.firstWhere(
      (connection) => connection.id == id,
      orElse: () => throw StateError('OBS connection "$id" no longer exists.'),
    );
  }

  ObsConnectionChoice _connectionChoice(ResourceData resource) {
    final config = resource.config;
    final host = config['host']?.toString().trim() ?? '';
    return ObsConnectionChoice(
      id: resource.id,
      name: resource.name,
      host: host,
      port: _port(config['port']) ?? 4455,
      isLocal:
          config['local'] == true ||
          (config['local'] == null && _isLocalHost(host)),
      installPath: config['installPath']?.toString(),
    );
  }

  Future<String> _localNetworkAddress() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    final addresses = [
      for (final interface in interfaces)
        for (final address in interface.addresses)
          if (!address.isLoopback && !address.isLinkLocal) address.address,
    ];
    final private = addresses.where(_isPrivateIpv4).firstOrNull;
    if (private != null) return private;
    if (addresses.isNotEmpty) return addresses.first;
    throw StateError('Could not find this computer\'s LAN address.');
  }
}

bool _isOverlayUrl(Object? raw, String overlayId) {
  final uri = Uri.tryParse(raw?.toString() ?? '');
  if (uri == null || uri.scheme != 'http') return false;
  final segments = uri.pathSegments;
  return segments.length >= 2 &&
      segments[0] == 'overlays' &&
      segments[1] == overlayId;
}

bool _sameDimension(Object? value, int expected) => value is num
    ? value.toDouble() == expected.toDouble()
    : int.tryParse('$value') == expected;

bool _isLocalHost(String host) =>
    host == 'localhost' || host == '127.0.0.1' || host == '::1';

bool _isPrivateIpv4(String value) =>
    value.startsWith('10.') ||
    value.startsWith('192.168.') ||
    (value.startsWith('172.') &&
        (int.tryParse(value.split('.').elementAtOrNull(1) ?? '') ?? 0) >= 16 &&
        (int.tryParse(value.split('.').elementAtOrNull(1) ?? '') ?? 255) <= 31);

int? _port(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value');

Future<String?> _obsExecutable(String? installPath) async {
  final configured = installPath?.trim();
  final candidates = <String>[
    if (configured?.isNotEmpty == true &&
        configured!.toLowerCase().endsWith('.exe'))
      configured,
    if (configured?.isNotEmpty == true &&
        !configured!.toLowerCase().endsWith('.exe'))
      '${Directory(configured).path}${Platform.pathSeparator}bin${Platform.pathSeparator}64bit${Platform.pathSeparator}obs64.exe',
    if (Platform.environment['ProgramFiles'] case final String programFiles)
      '$programFiles${Platform.pathSeparator}obs-studio${Platform.pathSeparator}bin${Platform.pathSeparator}64bit${Platform.pathSeparator}obs64.exe',
  ];
  for (final candidate in candidates) {
    if (await File(candidate).exists()) return candidate;
  }
  return null;
}
