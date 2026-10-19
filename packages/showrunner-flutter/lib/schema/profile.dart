import '../graph/domain/automation_document.dart';
import 'json.dart';
import '../graph/definitions/showrunner_graph_types.dart';

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
  final AutomationDocument activationAutomation;
  final AutomationDocument deactivationAutomation;
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
    final triggers = _maps(json['triggers']);
    _validateTriggers(triggers);
    return ShowRunnerProfile(
      name: json['name'] as String? ?? '',
      activationMode: json['activationMode'] as String? ?? 'toggle',
      triggers: triggers,
      activationCondition: json['activationCondition'] is Map
          ? Map<String, dynamic>.from(json['activationCondition'] as Map)
          : const <String, dynamic>{},
      activationAutomation: AutomationDocument.fromJson(
        _map(json['activationAutomation']),
      ),
      deactivationAutomation: AutomationDocument.fromJson(
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

void _validateTriggers(List<JsonMap> triggers) {
  for (final trigger in triggers) {
    if (trigger.keys.any(
      (key) => !{'id', 'description', 'automation'}.contains(key),
    )) {
      throw const FormatException('Unsupported profile event fields.');
    }
    if (trigger['id'] is! String || (trigger['id'] as String).isEmpty) {
      throw const FormatException('Profile trigger must contain an id.');
    }
    final automation = trigger['automation'];
    if (automation is! Map) {
      throw const FormatException(
        'Profile triggers must contain a version-1 automation document.',
      );
    }
    final parsedAutomation = AutomationDocument.fromJson(
      Map<String, dynamic>.from(automation),
    );
    final triggerNodes = parsedAutomation
        .graph
        .spaces[mainAutomationSpace]!
        .nodes
        .values
        .where((node) => decodeContractNodeType(node.type, 'trigger') != null);
    if (triggerNodes.isEmpty) {
      throw const FormatException(
        'Profile event automation requires a trigger node.',
      );
    }
  }
}
