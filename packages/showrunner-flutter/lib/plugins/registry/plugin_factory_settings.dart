Duration positivePluginDuration(Object? value, Duration fallback) {
  final seconds = value is num ? value.toDouble() : double.tryParse('$value');
  if (seconds == null || !seconds.isFinite || seconds <= 0) return fallback;
  return Duration(milliseconds: (seconds * 1000).round());
}

int pluginPort(Object? value, int fallback) {
  final port = value is num ? value.toInt() : int.tryParse('$value');
  return port != null && port >= 1 && port <= 65535 ? port : fallback;
}

int positivePluginInt(Object? value, int fallback) {
  final number = value is num ? value.toInt() : int.tryParse('$value');
  return number != null && number > 0 ? number : fallback;
}

double pluginPercentage(Object? value, double fallback) {
  final number = value is num ? value.toDouble() : double.tryParse('$value');
  if (number == null || !number.isFinite) return fallback;
  return number.clamp(0, 100).toDouble();
}
