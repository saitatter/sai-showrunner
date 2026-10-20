import '../../runtime/expression.dart';

enum ProviderPlatform { twitch, youtube }

enum ProviderEventVisibility { public, private }

/// The adapter discards its HTTP/socket wrapper here. Only immutable domain
/// fields cross this boundary; credentials are removed recursively.
final class ProviderEventEnvelope {
  ProviderEventEnvelope({
    required this.platform,
    required this.eventType,
    required this.occurredAt,
    required RuntimeMap payload,
    this.providerEventId,
    this.channelId,
    this.accountId,
    this.visibility = ProviderEventVisibility.public,
  }) : safePayload = _safeMap(payload, 0);

  final ProviderPlatform platform;
  final String eventType;
  final String? providerEventId;
  final String? channelId;
  final String? accountId;
  final DateTime occurredAt;
  final ProviderEventVisibility visibility;
  final RuntimeMap safePayload;
}

const _credentials = {
  'authorization',
  'accesstoken',
  'refreshtoken',
  'clientsecret',
  'apppassword',
  'password',
  'apikey',
};

final _credentialSeparators = RegExp('[_-]');

RuntimeMap _safeMap(Map value, int depth) {
  if (depth > 32) {
    throw const FormatException(
      'Provider event exceeds the domain nesting limit.',
    );
  }
  return Map<String, dynamic>.unmodifiable({
    for (final entry in value.entries)
      if (entry.key is String &&
          !_credentials.contains(
            (entry.key as String).toLowerCase().replaceAll(
              _credentialSeparators,
              '',
            ),
          ))
        entry.key as String: _safeValue(entry.value, depth + 1),
  });
}

Object? _safeValue(Object? value, int depth) {
  if (depth > 32) {
    throw const FormatException(
      'Provider event exceeds the domain nesting limit.',
    );
  }
  if (value is Map) return _safeMap(value, depth);
  if (value is List) {
    return List.unmodifiable(value.map((item) => _safeValue(item, depth + 1)));
  }
  if (value == null || value is String || value is bool || value is num) {
    return value;
  }
  throw const FormatException(
    'Provider event contains a non-JSON domain field.',
  );
}
