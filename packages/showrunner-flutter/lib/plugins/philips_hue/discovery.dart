import 'dart:convert';
import 'dart:io';

typedef HueDiscoveryRequest =
    Future<dynamic> Function(
      String method,
      Uri uri,
      Map<String, dynamic>? body,
    );

typedef HueDiscoveryDelay = Future<void> Function(Duration duration);

final class HueBridgePairing {
  const HueBridgePairing({required this.host, required this.applicationKey});

  final String host;
  final String applicationKey;
}

final class PhilipsHueDiscoveryService {
  const PhilipsHueDiscoveryService({
    this.request = _request,
    this.delay = _delay,
    this.attempts = 6,
  });

  final HueDiscoveryRequest request;
  final HueDiscoveryDelay delay;
  final int attempts;

  Future<HueBridgePairing?> findAndPair() async {
    final discovered = await request(
      'GET',
      Uri.parse('https://discovery.meethue.com/'),
      null,
    );
    if (discovered is! List) return null;

    for (final raw in discovered.whereType<Map>()) {
      final host = raw['internalipaddress']?.toString().trim() ?? '';
      if (host.isEmpty || !await _isBridge(host)) continue;
      final applicationKey = await _pair(host);
      if (applicationKey != null) {
        return HueBridgePairing(host: host, applicationKey: applicationKey);
      }
    }
    return null;
  }

  Future<bool> _isBridge(String host) async {
    try {
      final result = await request(
        'GET',
        Uri.parse('http://$host/api/0/config'),
        null,
      );
      return result is Map &&
          result['name']?.toString().isNotEmpty == true &&
          result['bridgeid']?.toString().isNotEmpty == true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _pair(String host) async {
    final count = attempts < 1 ? 1 : attempts;
    for (var index = 0; index < count; index++) {
      try {
        final response = await request('POST', Uri.parse('http://$host/api'), {
          'devicetype':
              'ShowRunner#${Platform.environment['USERNAME'] ?? Platform.environment['USER'] ?? 'user'}',
        });
        final key = _applicationKey(response);
        if (key != null) return key;
      } catch (_) {
        // A bridge can reject pairing until its physical button is pressed.
      }
      if (index < count - 1) await delay(const Duration(seconds: 10));
    }
    return null;
  }
}

String? _applicationKey(dynamic response) {
  if (response is! List || response.isEmpty) return null;
  final first = response.first;
  if (first is! Map) return null;
  final success = first['success'];
  if (success is! Map) return null;
  final key = success['username']?.toString().trim();
  return key == null || key.isEmpty ? null : key;
}

Future<dynamic> _request(
  String method,
  Uri uri,
  Map<String, dynamic>? body,
) async {
  final client = HttpClient()
    ..badCertificateCallback = (certificate, host, port) => true;
  try {
    final httpRequest = await client.openUrl(method, uri);
    httpRequest.headers.contentType = ContentType.json;
    if (body != null) httpRequest.write(jsonEncode(body));
    final response = await httpRequest.close();
    final text = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Philips Hue discovery request failed (${response.statusCode}): $text',
      );
    }
    return text.isEmpty ? null : jsonDecode(text);
  } finally {
    client.close(force: true);
  }
}

Future<void> _delay(Duration duration) => Future<void>.delayed(duration);
