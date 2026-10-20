import 'dart:convert';

final class SanitizedExecutionResult {
  const SanitizedExecutionResult(this.value, this.truncated);

  final Object? value;
  final bool truncated;
}

SanitizedExecutionResult sanitizeExecutionResult(Object? value) {
  final sanitized = _sanitize(value, depth: 0);
  try {
    final encoded = jsonEncode(sanitized.value);
    if (encoded.length <= 16 * 1024) return sanitized;
    return SanitizedExecutionResult(
      boundedTraceString(encoded, 16 * 1024),
      true,
    );
  } on Object {
    return const SanitizedExecutionResult('<unserializable result>', true);
  }
}

SanitizedExecutionResult _sanitize(Object? value, {required int depth}) {
  if (value == null || value is num || value is bool) {
    return SanitizedExecutionResult(value, false);
  }
  if (value is String) {
    final truncated = value.length > 4096;
    return SanitizedExecutionResult(boundedTraceString(value, 4096), truncated);
  }
  if (depth >= 5) return const SanitizedExecutionResult('<max depth>', true);
  if (value is Map) {
    final result = <String, Object?>{};
    var truncated = false;
    for (final entry in value.entries.take(100)) {
      final item = _sanitize(entry.value, depth: depth + 1);
      result[entry.key.toString()] = item.value;
      truncated = truncated || item.truncated;
    }
    if (value.length > 100) truncated = true;
    return SanitizedExecutionResult(result, truncated);
  }
  if (value is Iterable) {
    final result = <Object?>[];
    var truncated = false;
    for (final item in value.take(50)) {
      final sanitized = _sanitize(item, depth: depth + 1);
      result.add(sanitized.value);
      truncated = truncated || sanitized.truncated;
    }
    if (value.length > 50) truncated = true;
    return SanitizedExecutionResult(result, truncated);
  }
  return SanitizedExecutionResult(
    boundedTraceString(value.toString(), 4096),
    true,
  );
}

String boundedTraceString(String value, int limit) =>
    value.length <= limit ? value : '${value.substring(0, limit)}â€¦';
