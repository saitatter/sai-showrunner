/// Bounded JSON values shared with authenticated browser/remote consumers.
bool isPrivatePublicField(String key) => const {
  'token',
  'accesstoken',
  'refreshtoken',
  'clientsecret',
  'password',
  'credentials',
  'authorization',
  'apikey',
  'privatekey',
  'browsersecret',
  'connectionstring',
  'filepath',
  'localpath',
}.contains(key.replaceAll(RegExp('[^a-zA-Z]'), '').toLowerCase());

Object? projectPublicValue(Object? value) =>
    _PublicValueProjector().project(value, 0);

final class _PublicValueProjector {
  var remaining = 1024;
  var stringBudget = 8192;
  Object? project(Object? value, int depth) {
    if (remaining-- <= 0 || depth > 8) return null;
    if (value == null || value is bool) return value;
    if (value is num) return value.isFinite ? value : null;
    if (value is String) {
      if (value.length > 4096 ||
          value.length > stringBudget ||
          RegExp(
            r'^(?:[a-zA-Z]:[\\/]|\\\\|file:|/(?:Users|home|root|tmp|var|etc|mnt)/)',
            caseSensitive: false,
          ).hasMatch(value)) {
        return null;
      }
      stringBudget -= value.length;
      return value;
    }
    if (value is List) {
      final result = <Object?>[];
      for (final item in value.take(64)) {
        if (remaining <= 0) break;
        result.add(project(item, depth + 1));
      }
      return result;
    }
    if (value is Map) {
      final result = <String, dynamic>{};
      for (final entry in value.entries.take(64)) {
        if (remaining <= 0) break;
        if (entry.key is! String ||
            (entry.key as String).length > 128 ||
            isPrivatePublicField(entry.key as String)) {
          continue;
        }
        result[entry.key as String] = project(entry.value, depth + 1);
      }
      return result;
    }
    return null;
  }
}
