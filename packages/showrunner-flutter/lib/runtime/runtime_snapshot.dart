import 'expression.dart';

/// Snapshot JSON-like collections without serializing opaque runtime capabilities.
/// Reject cyclic/excessively nested input visibly instead of overflowing the stack.
RuntimeMap freezeRuntimeMap(Map value) => _freeze(value, 0) as RuntimeMap;
Object? _freeze(Object? value, int depth) {
  if (depth > 64) {
    throw const FormatException('Runtime snapshot exceeds its nesting limit.');
  }
  if (value is Map) {
    return Map<String, Object?>.unmodifiable({
      for (final entry in value.entries)
        entry.key as String: _freeze(entry.value, depth + 1),
    });
  }
  if (value is List) {
    return List<Object?>.unmodifiable(
      value.map((item) => _freeze(item, depth + 1)),
    );
  }
  return value;
}

Map<String, dynamic> copyRuntimeMap(Map value) =>
    _copy(value, 0) as Map<String, dynamic>;
Object? _copy(Object? value, int depth) {
  if (depth > 64) {
    throw const FormatException('Runtime snapshot exceeds its nesting limit.');
  }
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key as String: _copy(entry.value, depth + 1),
    };
  }
  if (value is List) {
    return value.map((item) => _copy(item, depth + 1)).toList();
  }
  return value;
}
