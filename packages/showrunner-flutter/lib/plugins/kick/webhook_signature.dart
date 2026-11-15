import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

typedef KickPublicKeyLoader = Future<String> Function();

/// Verifies the exact bytes specified by Kick, outside the UI isolate.
/// https://docs.kick.com/events/webhook-security
///
/// Fetch keys from Kick's public-key endpoint rather than embedding a key that
/// cannot follow rotation. Refreshes are single-flight and throttled, including
/// failed refreshes, so invalid signatures cannot cause unbounded key fetches.
final class KickWebhookSignatureVerifier {
  KickWebhookSignatureVerifier({
    required this.loadPublicKey,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final KickPublicKeyLoader loadPublicKey;
  final DateTime Function() _now;
  String? _key;
  DateTime? _loadedAt;
  DateTime? _attemptedAt;
  Future<String?>? _loading;
  bool _closed = false;
  int _active = 0;

  static const replayWindow = Duration(minutes: 5);
  static const maxConcurrentVerifications = 4;

  bool get busy => _active >= maxConcurrentVerifications;

  Future<bool> verify({
    required String messageId,
    required String timestamp,
    required String signature,
    required Uint8List body,
  }) async {
    if (_closed || busy || body.length > 262144) return false;
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(messageId) ||
        timestamp.length > 64 ||
        !RegExp(
          r'^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$',
        ).hasMatch(timestamp) ||
        signature.length > 1400) {
      return false;
    }
    final sentAt = DateTime.tryParse(timestamp);
    if (sentAt == null || _now().difference(sentAt).abs() > replayWindow) {
      return false;
    }
    Uint8List decoded;
    try {
      decoded = base64Decode(signature);
    } on FormatException {
      return false;
    }
    if (decoded.length < 256 || decoded.length > 1024) return false;
    _active++;
    try {
      final payload = Uint8List.fromList([
        ...utf8.encode('$messageId.$timestamp.'),
        ...body,
      ]);
      final key = await _getKey();
      if (_closed || key == null) return false;
      if (await _check(key, payload, decoded)) return !_closed;
      // One retry allows a rotated key without accepting arbitrary keys sent
      // in webhook headers. The loader is always the trusted Kick endpoint.
      final fresh = await _getKey(refresh: true);
      if (_closed || fresh == null || fresh == key) return false;
      return await _check(fresh, payload, decoded) && !_closed;
    } finally {
      _active--;
    }
  }

  Future<String?> _getKey({bool refresh = false}) {
    if (_closed) return Future.value(null);
    final pending = _loading;
    if (pending != null) return pending;
    final now = _now();
    if (!refresh &&
        _key != null &&
        now.difference(_loadedAt!) < const Duration(hours: 1)) {
      return Future.value(_key);
    }
    if (_attemptedAt != null &&
        now.difference(_attemptedAt!) < const Duration(seconds: 30)) {
      return Future.value(_key);
    }
    _attemptedAt = now;
    return _loading = _fetch();
  }

  Future<String?> _fetch() async {
    try {
      final key = await loadPublicKey().timeout(const Duration(seconds: 10));
      if (_closed || key.length > 4096) return null;
      // Validate in the worker when verifying; malformed server responses do
      // not expose their content through exceptions or diagnostic messages.
      _key = key;
      _loadedAt = _now();
      return key;
    } catch (_) {
      return null;
    } finally {
      _loading = null;
    }
  }

  void close() {
    _closed = true;
    _key = null;
  }
}

Future<bool> _check(String pem, Uint8List body, Uint8List signature) =>
    Isolate.run(() => _verifyRsa(pem, body, signature));

bool _verifyRsa(String pem, Uint8List body, Uint8List signature) {
  try {
    const begin = '-----BEGIN PUBLIC KEY-----';
    const end = '-----END PUBLIC KEY-----';
    final text = pem.trim();
    if (!text.startsWith(begin) || !text.endsWith(end)) return false;
    final der = base64Decode(
      text
          .substring(begin.length, text.length - end.length)
          .replaceAll(RegExp(r'\s'), ''),
    );
    final parser = ASN1Parser(der);
    final sequence = parser.nextObject();
    if (parser.hasNext() || sequence is! ASN1Sequence) return false;
    final elements = sequence.elements;
    if (elements == null || elements.length != 2) return false;
    final algorithm = elements[0];
    final bits = elements[1];
    if (algorithm is! ASN1Sequence || bits is! ASN1BitString) return false;
    final identifier = algorithm.elements?.firstOrNull;
    if (identifier is! ASN1ObjectIdentifier ||
        identifier.objectIdentifierAsString != '1.2.840.113549.1.1.1') {
      return false;
    }
    final bytes = bits.stringValues;
    if (bytes == null) return false;
    final keyParser = ASN1Parser(Uint8List.fromList(bytes));
    final key = keyParser.nextObject();
    if (keyParser.hasNext() || key is! ASN1Sequence) return false;
    final integers = key.elements;
    if (integers == null || integers.length != 2) return false;
    final n = integers[0];
    final e = integers[1];
    if (n is! ASN1Integer || e is! ASN1Integer) return false;
    final modulus = n.integer;
    final exponent = e.integer;
    if (modulus == null ||
        exponent == null ||
        modulus.isNegative ||
        modulus.bitLength < 2048 ||
        modulus.bitLength > 8192 ||
        exponent <= BigInt.one ||
        exponent.isEven ||
        signature.length != (modulus.bitLength + 7) ~/ 8) {
      return false;
    }
    final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
      ..init(
        false,
        PublicKeyParameter<RSAPublicKey>(RSAPublicKey(modulus, exponent)),
      );
    return signer.verifySignature(body, RSASignature(signature));
  } catch (_) {
    return false;
  }
}
