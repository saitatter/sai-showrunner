import '../../domain/errors/unsupported_document_exception.dart';
import 'package:sai_nodes_core/sai_nodes_core.dart';

const mainAutomationSpace = 'space:main';
const automationHostMetadata = 'showrunner';

final class AutomationParameter {
  AutomationParameter({
    required this.id,
    required this.name,
    this.type = 'core.any',
    Object? defaultValue,
  }) : _default = freezeJson({'value': defaultValue}) {
    if (id.isEmpty || name.isEmpty) {
      throw ArgumentError('Parameters require stable IDs and names.');
    }
  }
  final String id, name, type;
  final GraphJson _default;
  Object? get defaultValue => _default['value'];
  GraphJson toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'defaultValue': defaultValue,
  };
  factory AutomationParameter.fromJson(GraphJson json) {
    _fields(json, {'id', 'name', 'type', 'defaultValue'}, 'parameter');
    return AutomationParameter(
      id: _string(json, 'id'),
      name: _string(json, 'name'),
      type: _string(json, 'type'),
      defaultValue: json['defaultValue'],
    );
  }
}

final class AutomationSubgraph {
  AutomationSubgraph({
    required this.id,
    required this.name,
    required this.entryNodeId,
    Iterable<AutomationParameter> parameters = const [],
    Iterable<AutomationParameter> outputs = const [],
  }) : parameters = List.unmodifiable(parameters),
       outputs = List.unmodifiable(outputs) {
    if (id.isEmpty) throw ArgumentError('Subgraphs require a stable ID.');
    for (final ports in [this.parameters, this.outputs]) {
      if (ports.map((port) => port.id).toSet().length != ports.length ||
          ports.map((port) => port.name).toSet().length != ports.length) {
        throw ArgumentError(
          'Subgraph parameter/output IDs and names must be unique.',
        );
      }
    }
  }
  final String id, name, entryNodeId;
  final List<AutomationParameter> parameters, outputs;
  String get spaceId => 'space:subgraph:$id';
  GraphJson toJson() => {
    'id': id,
    'name': name,
    'entryNodeId': entryNodeId,
    'parameters': parameters.map((port) => port.toJson()).toList(),
    'outputs': outputs.map((port) => port.toJson()).toList(),
  };
  factory AutomationSubgraph.fromJson(GraphJson json) {
    _fields(json, {
      'id',
      'name',
      'entryNodeId',
      'parameters',
      'outputs',
    }, 'subgraph');
    return AutomationSubgraph(
      id: _string(json, 'id'),
      name: _string(json, 'name'),
      entryNodeId: _string(json, 'entryNodeId'),
      parameters: _objects(
        json['parameters'],
        'parameters',
      ).map(AutomationParameter.fromJson),
      outputs: _objects(
        json['outputs'],
        'outputs',
      ).map(AutomationParameter.fromJson),
    );
  }
  AutomationSubgraph copyWith({
    String? name,
    String? entryNodeId,
    Iterable<AutomationParameter>? parameters,
    Iterable<AutomationParameter>? outputs,
  }) => AutomationSubgraph(
    id: id,
    name: name ?? this.name,
    entryNodeId: entryNodeId ?? this.entryNodeId,
    parameters: parameters ?? this.parameters,
    outputs: outputs ?? this.outputs,
  );
}

/// Canonical automation state. Host semantics live once in graph metadata so
/// graph transactions/history cover settings and subgraph signatures atomically.
/// The version-1 envelope projects that namespace outside graph metadata on disk.
final class AutomationDocument {
  AutomationDocument({
    required GraphDocument graph,
    Map<String, AutomationSubgraph> subgraphs = const {},
    GraphJson settings = const {},
    GraphJson metadata = const {},
  }) : graph = graph.copyWith(
         metadata: {
           ...graph.metadata,
           automationHostMetadata: {
             'settings': settings,
             'subgraphs': {
               for (final entry in subgraphs.entries)
                 entry.key: entry.value.toJson(),
             },
             'metadata': metadata,
           },
         },
       ) {
    _validateHost();
  }
  AutomationDocument.fromGraph(this.graph) {
    _validateHost();
  }
  final GraphDocument graph;
  String get id => graph.id;
  GraphJson get _host =>
      _object(graph.metadata[automationHostMetadata], 'showrunner metadata');
  GraphJson get settings => _object(_host['settings'], 'settings');
  GraphJson get metadata => _object(_host['metadata'], 'metadata');
  Map<String, AutomationSubgraph> get subgraphs => Map.unmodifiable(
    _object(_host['subgraphs'], 'subgraphs').map(
      (id, value) => MapEntry(
        id,
        AutomationSubgraph.fromJson(_object(value, 'subgraph $id')),
      ),
    ),
  );
  String get entryNodeId => settings['entryNodeId'] as String? ?? '';
  String? get queueId =>
      settings['queue'] is String && (settings['queue'] as String).isNotEmpty
      ? settings['queue'] as String
      : null;
  factory AutomationDocument.empty({String? id}) => AutomationDocument(
    graph: GraphDocument(
      id: id ?? newGraphId(),
      spaces: {mainAutomationSpace: GraphSpace(id: mainAutomationSpace)},
    ),
  );
  void _validateHost() {
    if (!graph.spaces.containsKey(mainAutomationSpace)) {
      throw const FormatException('Automation requires space:main.');
    }
    settings;
    metadata;
    final raw = _object(_host['subgraphs'], 'subgraphs');
    for (final entry in raw.entries) {
      final subgraph = AutomationSubgraph.fromJson(
        _object(entry.value, 'subgraph ${entry.key}'),
      );
      if (entry.key != subgraph.id) {
        throw const FormatException('Subgraph key must match its stable ID.');
      }
    }
  }

  GraphJson toJson() {
    final serialized = graph.toJson();
    serialized['metadata'] = {...graph.metadata}
      ..remove(automationHostMetadata);
    return {
      'schemaVersion': 1,
      'id': id,
      'graph': serialized,
      'subgraphs': _host['subgraphs'],
      'settings': settings,
      'metadata': metadata,
    };
  }

  factory AutomationDocument.fromJson(GraphJson json) {
    if (json['schemaVersion'] is int && json['schemaVersion'] != 1) {
      throw const UnsupportedDocumentException(
        'Automation requires schemaVersion 1.',
      );
    }
    if (json['schemaVersion'] is! int || json['schemaVersion'] != 1) {
      throw const FormatException('Automation requires schemaVersion 1.');
    }
    if (json.keys.any(
      (key) => !{
        'schemaVersion',
        'id',
        'graph',
        'subgraphs',
        'settings',
        'metadata',
      }.contains(key),
    )) {
      throw const UnsupportedDocumentException(
        'Unsupported automation fields.',
      );
    }
    final graph = GraphDocument.fromJson(_object(json['graph'], 'graph'));
    if (_string(json, 'id') != graph.id) {
      throw const FormatException('Automation and graph IDs must match.');
    }
    if (graph.metadata.containsKey(automationHostMetadata)) {
      throw const FormatException(
        'Host metadata must use the automation envelope.',
      );
    }
    return AutomationDocument(
      graph: graph,
      subgraphs: _object(json['subgraphs'], 'subgraphs').map(
        (id, value) => MapEntry(
          id,
          AutomationSubgraph.fromJson(_object(value, 'subgraph $id')),
        ),
      ),
      settings: _object(json['settings'], 'settings'),
      metadata: _object(json['metadata'], 'metadata'),
    );
  }
  AutomationDocument withSettings(GraphJson value) =>
      AutomationDocument.fromGraph(
        graph.copyWith(
          metadata: {
            ...graph.metadata,
            automationHostMetadata: {..._host, 'settings': value},
          },
        ),
      );
  AutomationDocument withMetadata(GraphJson value) =>
      AutomationDocument.fromGraph(
        graph.copyWith(
          metadata: {
            ...graph.metadata,
            automationHostMetadata: {..._host, 'metadata': value},
          },
        ),
      );
  AutomationDocument withSubgraphs(Map<String, AutomationSubgraph> value) =>
      AutomationDocument.fromGraph(
        graph.copyWith(
          metadata: {
            ...graph.metadata,
            automationHostMetadata: {
              ..._host,
              'subgraphs': {
                for (final entry in value.entries)
                  entry.key: entry.value.toJson(),
              },
            },
          },
        ),
      );
}

GraphJson _object(Object? value, String label) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw FormatException('$label must be an object.');
  }
  return Map<String, Object?>.unmodifiable(value.cast<String, Object?>());
}

String _string(GraphJson value, String key) {
  final result = value[key];
  if (result is! String) throw FormatException('$key must be a string.');
  return result;
}

List<GraphJson> _objects(Object? value, String label) {
  if (value is! List) throw FormatException('$label must be an array.');
  return value.map((item) => _object(item, label)).toList();
}

void _fields(GraphJson json, Set<String> allowed, String label) {
  if (json.keys.any((key) => !allowed.contains(key))) {
    throw UnsupportedDocumentException('Unsupported $label fields.');
  }
}
