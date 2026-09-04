import 'automation.dart';

JsonMap emptyInlineAutomation() => const {
  'schemaVersion': 2,
  'graph': {'nodes': [], 'edges': [], 'entryNodeId': ''},
  'subgraphs': [],
  'dataWires': [],
  'variableNodes': [],
  'triggerNodes': [],
};

final class StreamPlanSegmentData {
  const StreamPlanSegmentData({
    required this.id,
    required this.name,
    required this.components,
    required this.activationAutomation,
    required this.deactivationAutomation,
  });

  final String id;
  final String name;
  final JsonMap components;
  final JsonMap activationAutomation;
  final JsonMap deactivationAutomation;

  factory StreamPlanSegmentData.fromJson(JsonMap json) => StreamPlanSegmentData(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    components: _map(json['components']),
    activationAutomation: _automation(json['activationAutomation']),
    deactivationAutomation: _automation(json['deactivationAutomation']),
  );

  JsonMap toJson() => {
    'id': id,
    'name': name,
    'components': components,
    'activationAutomation': activationAutomation,
    'deactivationAutomation': deactivationAutomation,
  };
}

final class StreamPlanData {
  const StreamPlanData({
    required this.name,
    required this.activationAutomation,
    required this.deactivationAutomation,
    required this.segments,
  });

  final String name;
  final JsonMap activationAutomation;
  final JsonMap deactivationAutomation;
  final List<StreamPlanSegmentData> segments;

  factory StreamPlanData.fromConfig(JsonMap config) => StreamPlanData(
    name: config['name']?.toString() ?? '',
    activationAutomation: _automation(config['activationAutomation']),
    deactivationAutomation: _automation(config['deactivationAutomation']),
    segments: config['segments'] is List
        ? (config['segments'] as List)
              .whereType<Map>()
              .map(
                (item) => StreamPlanSegmentData.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              )
              .toList()
        : const [],
  );

  JsonMap toConfig() => {
    'name': name,
    'activationAutomation': activationAutomation,
    'deactivationAutomation': deactivationAutomation,
    'segments': segments.map((segment) => segment.toJson()).toList(),
  };
}

JsonMap _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

JsonMap _automation(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : emptyInlineAutomation();
