import 'automation.dart';

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
    if (timeout != null) 'timeout': timeout!.inMilliseconds,
  };

  factory QueueConfig.fromJson(JsonMap input) {
    final json = Map<String, dynamic>.from(input);
    final known = {'name', 'paused', 'gap', 'timeout'};
    Duration? duration(dynamic value) =>
        value is num ? Duration(milliseconds: value.toInt()) : null;
    return QueueConfig(
      name: json['name'] as String? ?? '',
      paused: json['paused'] == true,
      gap: duration(json['gap']) ?? Duration.zero,
      timeout: duration(json['timeout']) ?? const Duration(seconds: 30),
      extra: json..removeWhere((key, _) => known.contains(key)),
    );
  }
}
