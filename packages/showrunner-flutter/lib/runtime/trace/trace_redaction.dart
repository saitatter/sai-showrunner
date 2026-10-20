import 'dart:convert';
import '../../domain/errors/showrunner_error.dart';

/// Only trusted runtime code may opt result fields into text/value capture.
/// Credentials and private/resource containers remain denied even with opt-in.
final class TraceValuePolicy {
  const TraceValuePolicy._(this.publicFields);
  static const metadata = TraceValuePolicy._({});
  factory TraceValuePolicy.publicFields(Iterable<String> fields) =>
      TraceValuePolicy._(Set.unmodifiable(fields));
  final Set<String> publicFields;
}

final class SanitizedExecutionResult {
  const SanitizedExecutionResult(this.value, this.truncated);
  final Object? value;
  final bool truncated;
}

const _denied = {
  'authorization',
  'accesstoken',
  'refreshtoken',
  'clientsecret',
  'apppassword',
  'password',
  'apikey',
  'secret',
  'credentials',
  'credential',
  'token',
  'cookie',
  'setcookie',
  'sessionkey',
  'resource',
  'resourceconfig',
  'config',
  'viewer',
  'viewerdata',
  'user',
  'userdata',
  'whisper',
  'whispers',
  'privatemessage',
  'email',
  'phone',
  'address',
  'message',
  'messagetext',
  'text',
  'raw',
  'rawpayload',
  'payload',
};
const _booleanMetadata = {
  'ok',
  'done',
  'success',
  'completed',
  'queued',
  'played',
  'spoken',
  'aborted',
  'cancelled',
};
const _statusMetadata = {
  'ok',
  'success',
  'failed',
  'pending',
  'queued',
  'completed',
  'running',
  'cancelled',
  'cancelling',
  'stopped',
  'ready',
  'error',
  'unavailable',
  'disconnected',
};
final _separators = RegExp(r'[^a-z0-9]');

SanitizedExecutionResult sanitizeExecutionResult(
  Object? value, {
  TraceValuePolicy policy = TraceValuePolicy.metadata,
}) {
  final sanitized = _sanitize(value, depth: 0, policy: policy);
  try {
    final encoded = jsonEncode(sanitized.value);
    if (encoded.length <= 16 * 1024) return sanitized;
    return SanitizedExecutionResult(
      boundedTraceString(encoded, 16 * 1024),
      true,
    );
  } on Object {
    return const SanitizedExecutionResult('<result omitted>', true);
  }
}

SanitizedExecutionResult _sanitize(
  Object? value, {
  required int depth,
  required TraceValuePolicy policy,
  bool publicValue = false,
}) {
  if (value == null) return const SanitizedExecutionResult(null, false);
  if (depth >= 5) return const SanitizedExecutionResult('<max depth>', true);
  if (value is String) {
    if (!publicValue) {
      return const SanitizedExecutionResult('<value omitted>', true);
    }
    return SanitizedExecutionResult(
      boundedTraceString(value, 4096),
      value.length > 4096,
    );
  }
  if (value is num || value is bool) {
    return publicValue
        ? SanitizedExecutionResult(value, false)
        : const SanitizedExecutionResult('<value omitted>', true);
  }
  if (value is Map) {
    final result = <String, Object?>{};
    var truncated = value.length > 100;
    var redacted = 0;
    for (final entry in value.entries.take(100)) {
      final key = entry.key;
      if (key is! String ||
          _denied.contains(key.toLowerCase().replaceAll(_separators, ''))) {
        redacted++;
        continue;
      }
      final explicit = publicValue || policy.publicFields.contains(key);
      final safeBoolean = _booleanMetadata.contains(key) && entry.value is bool;
      final safeStatus =
          key == 'status' && _statusMetadata.contains(entry.value);
      if (!explicit && !safeBoolean && !safeStatus) {
        redacted++;
        continue;
      }
      final item = _sanitize(
        entry.value,
        depth: depth + 1,
        policy: policy,
        publicValue: explicit || safeBoolean || safeStatus,
      );
      result[key] = item.value;
      truncated = truncated || item.truncated;
    }
    if (redacted > 0) {
      result['_redactedFields'] = redacted;
      truncated = true;
    }
    return SanitizedExecutionResult(
      Map<String, Object?>.unmodifiable(result),
      truncated,
    );
  }
  if (value is Iterable && publicValue) {
    final result = <Object?>[];
    final sample = value.take(51).toList(growable: false);
    var truncated = sample.length > 50;
    for (final item in sample.take(50)) {
      final next = _sanitize(
        item,
        depth: depth + 1,
        policy: policy,
        publicValue: true,
      );
      result.add(next.value);
      truncated = truncated || next.truncated;
    }
    return SanitizedExecutionResult(
      List<Object?>.unmodifiable(result),
      truncated,
    );
  }
  // Opaque values and exceptions must never invoke an untrusted toString here.
  return const SanitizedExecutionResult('<value omitted>', true);
}

String safeTraceErrorMessage(Object error) => error is ShowRunnerError
    ? '${error.code}${error.pluginId == null ? '' : ' (${error.pluginId!.value})'}'
    : '${error.runtimeType}: execution failed (details omitted).';

String boundedTraceString(String value, int limit) =>
    value.length <= limit ? value : '${value.substring(0, limit)}…';
