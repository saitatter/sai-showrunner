import 'automation.dart';

final class ShowRunnerProfile {
  const ShowRunnerProfile({
    required this.name,
    required this.activationMode,
    required this.triggers,
    required this.activationCondition,
    required this.activationAutomation,
    required this.deactivationAutomation,
    this.extra = const <String, dynamic>{},
  });

  final String name;
  final String activationMode;
  final List<JsonMap> triggers;
  final JsonMap activationCondition;
  final AutomationData activationAutomation;
  final AutomationData deactivationAutomation;
  final JsonMap extra;

  JsonMap toJson() => {
    ...extra,
    'name': name,
    'activationMode': activationMode,
    'triggers': triggers,
    'activationCondition': activationCondition,
    'activationAutomation': activationAutomation.toJson(),
    'deactivationAutomation': deactivationAutomation.toJson(),
  };

  factory ShowRunnerProfile.fromJson(JsonMap input) {
    final json = Map<String, dynamic>.from(input);
    return ShowRunnerProfile(
      name: json['name'] as String? ?? '',
      activationMode: json['activationMode'] as String? ?? 'toggle',
      triggers: _maps(json['triggers']),
      activationCondition: json['activationCondition'] is Map
          ? Map<String, dynamic>.from(json['activationCondition'] as Map)
          : const <String, dynamic>{},
      activationAutomation: AutomationData.fromJson(
        _map(json['activationAutomation']),
      ),
      deactivationAutomation: AutomationData.fromJson(
        _map(json['deactivationAutomation']),
      ),
      extra: json
        ..removeWhere(
          (key, _) => {
            'name',
            'activationMode',
            'triggers',
            'activationCondition',
            'activationAutomation',
            'deactivationAutomation',
          }.contains(key),
        ),
    );
  }
}

JsonMap _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

List<JsonMap> _maps(dynamic value) => value is List
    ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList()
    : <JsonMap>[];
