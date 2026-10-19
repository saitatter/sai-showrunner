part of '../satellite.dart';

/// Raw Azure Web PubSub signaling used by remote satellite clients.
///
/// The cloud endpoint already authenticates the connection with the Twitch
/// token. Only the three satellite signaling events are surfaced to the
/// connection managers; unrelated PubSub traffic is ignored.
final class SatelliteSignalingController extends ChangeNotifier {
  SatelliteSignalingController({
    required this.dataService,
    this.negotiator = _negotiateSatellite,
    this.socketFactory = _connectSatelliteSocket,
  });

  final ShowRunnerDataService dataService;
  final SatelliteSignalingNegotiator negotiator;
  final SatelliteSignalingSocketFactory socketFactory;

  final _messages = StreamController<SatelliteSignalingMessage>.broadcast();
  CloudPubSubSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  bool _connected = false;
  Object? _lastError;

  Stream<SatelliteSignalingMessage> get messages => _messages.stream;
  bool get isConnected => _connected;
  Object? get lastError => _lastError;

  Future<void> start() async {
    if (_socket != null && _connected) return;
    final settings = await loadTwitchChannelSettings(dataService);
    final token = settings['accessToken']?.toString().trim() ?? '';
    if (token.isEmpty) {
      throw StateError(
        'Twitch access token is required for remote dashboard connections.',
      );
    }

    final url = await negotiator(token);
    final socket = await socketFactory(Uri.parse(url));
    await _closeSocket();
    _socket = socket;
    _subscription = socket.messages.listen(
      _handleMessage,
      onError: (Object error) {
        _lastError = error;
        _connected = false;
        notifyListeners();
      },
      onDone: () {
        _connected = false;
        _socket = null;
        notifyListeners();
      },
      cancelOnError: false,
    );
    _connected = true;
    _lastError = null;
    notifyListeners();
  }

  Future<void> send(String event, SatelliteJson data) async {
    final socket = _socket;
    if (!_connected || socket == null) {
      throw StateError('Remote dashboard signaling is not connected.');
    }
    socket.add(
      jsonEncode({
        'type': 'event',
        'event': 'satellite_$event',
        'dataType': 'json',
        'data': data,
      }),
    );
  }

  Future<void> stop() async {
    await _closeSocket();
    _connected = false;
    notifyListeners();
  }

  void _handleMessage(dynamic raw) {
    final decoded = raw is String
        ? _decodeJson(raw)
        : raw is Map
        ? Map<String, dynamic>.from(raw)
        : null;
    if (decoded is! Map) return;
    final payload = decoded['data'] is Map
        ? Map<String, dynamic>.from(decoded['data'] as Map)
        : decoded;
    if (payload['plugin']?.toString() != 'satellite') return;
    final event = payload['event']?.toString() ?? '';
    if (event != 'satelliteConnectionRequest' &&
        event != 'satelliteConnectionResponse' &&
        event != 'satelliteConnectionIceCandidate') {
      return;
    }
    final context = payload['context'];
    final data = context is Map
        ? Map<String, dynamic>.from(context)
        : Map<String, dynamic>.from(payload);
    _messages.add(SatelliteSignalingMessage(event: event, data: data));
  }

  Future<void> _closeSocket() async {
    await _subscription?.cancel();
    _subscription = null;
    final socket = _socket;
    _socket = null;
    await socket?.close();
  }

  @override
  void dispose() {
    _connected = false;
    unawaited(_closeSocket());
    unawaited(_messages.close());
    super.dispose();
  }
}
