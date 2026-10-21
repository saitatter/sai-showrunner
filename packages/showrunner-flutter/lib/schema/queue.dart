import 'json.dart';

final class QueueConfig {
  const QueueConfig({
    required this.name,
    this.paused = false,
    this.gap = Duration.zero,
    this.timeout = const Duration(seconds: 30),
    this.extra = const <String, dynamic>{},
  });

  final String name;
  final bool paused;
  final Duration gap;
  final Duration? timeout;
  final JsonMap extra;

  JsonMap toJson() => {
    ...extra,
    'name': name,
    'paused': paused,
    'gap': gap.inMilliseconds,
    'timeout': timeout?.inMilliseconds,
  };

  factory QueueConfig.fromJson(JsonMap input) {
    final json = Map<String, dynamic>.from(input);
    final known = {'name', 'paused', 'gap', 'timeout'};
    if (json['name'] != null && json['name'] is! String) {
      throw const FormatException('Queue name must be text.');
    }
    if (json['paused'] != null && json['paused'] is! bool) {
      throw const FormatException('Queue paused flag must be boolean.');
    }
    Duration? duration(String field) {
      final value = json[field];
      if (value == null) return null;
      if (value is! num ||
          !value.isFinite ||
          value < 0 ||
          value != value.toInt()) {
        throw const FormatException(
          'Queue timing must contain non-negative whole milliseconds.',
        );
      }
      return Duration(milliseconds: value.toInt());
    }

    return QueueConfig(
      name: json['name'] as String? ?? '',
      paused: json['paused'] == true,
      gap: duration('gap') ?? Duration.zero,
      timeout: json.containsKey('timeout')
          ? duration('timeout')
          : const Duration(seconds: 30),
      extra: json..removeWhere((key, _) => known.contains(key)),
    );
  }
}
