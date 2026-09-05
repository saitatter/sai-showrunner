import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

import '../../schema/automation.dart';
import '../../schema/profile.dart';
import '../filesystem/atomic_file.dart';
import 'legacy_detector.dart';
import 'migration_report.dart';

/// Converts pre-graph documents at the persistence boundary.
///
/// No runtime or widget code is involved here. The result is always decoded
/// by the strict V2 schema before it is returned to the application.
final class LegacyImportService {
  const LegacyImportService({
    this._detector = const LegacyAutomationDetector(),
  });

  final LegacyAutomationDetector _detector;

  AutomationMigrationResult importAutomation(JsonMap input) {
    final detection = _detector.detect(input);
    if (detection.kind == AutomationDocumentKind.v2) {
      return AutomationMigrationResult(
        automation: AutomationData.fromJson(input),
        report: MigrationReport(
          sourceSchemaVersion: input['schemaVersion'],
          documentKind: 'v2',
          actionCount: _countActions(input['graph']),
        ),
      );
    }
    if (!detection.needsMigration) {
      throw FormatException(
        detection.reason ?? 'Unsupported automation document.',
      );
    }

    final state = _MigrationState();
    final normalized = _normalizeAutomation(input, state: state);
    final automation = AutomationData.fromJson(normalized);
    return AutomationMigrationResult(
      automation: automation,
      report: MigrationReport(
        sourceSchemaVersion: input['schemaVersion'],
        documentKind: 'legacy',
        actionCount: state.actionCount,
        warnings: List.unmodifiable(state.warnings),
      ),
    );
  }

  ShowRunnerProfile importProfile(JsonMap input) {
    final normalized = _normalizeProfile(input);
    return ShowRunnerProfile.fromJson(normalized);
  }

  JsonMap normalizeAutomationMap(JsonMap input) =>
      _normalizeAutomation(input, state: _MigrationState());

  JsonMap normalizeProfileMap(JsonMap input) => _normalizeProfile(input);

  JsonMap normalizeStreamPlanMap(JsonMap input) {
    final result = Map<String, dynamic>.from(input);
    result['activationAutomation'] = _normalizeAutomation(
      _asMap(result['activationAutomation']),
      state: _MigrationState(),
    );
    result['deactivationAutomation'] = _normalizeAutomation(
      _asMap(result['deactivationAutomation']),
      state: _MigrationState(),
    );
    final segments = result['segments'];
    if (segments is List) {
      result['segments'] = [
        for (final raw in segments.whereType<Map>())
          _normalizeStreamPlanSegment(Map<String, dynamic>.from(raw)),
      ];
    }
    return result;
  }

  Future<AutomationMigrationResult> migrateAutomationFile(
    File file, {
    Directory? backupRoot,
  }) async {
    final result = importAutomation(await readStructuredMap(file));
    if (!result.report.migrated) return result;
    final backup = await backupOriginalFile(file, backupRoot: backupRoot);
    await writeAtomicText(
      file,
      const JsonEncoder.withIndent('  ').convert(result.automation.toJson()),
    );
    return result.withBackup(backup.path);
  }
}

final class _MigrationState {
  int actionCount = 0;
  final warnings = <String>[];
}

JsonMap _normalizeAutomation(JsonMap input, {required _MigrationState state}) {
  final result = Map<String, dynamic>.from(input);
  final rawGraph = result['graph'];
  final graph = rawGraph is Map && rawGraph['nodes'] is List
      ? _normalizeGraph(Map<String, dynamic>.from(rawGraph), state: state)
      : _graphFromLegacy(result['sequence'] ?? result['actions'], state: state);

  result['schemaVersion'] = 2;
  result['graph'] = graph;
  result['subgraphs'] = result['subgraphs'] is List
      ? [
          for (final raw in result['subgraphs'].whereType<Map>())
            _normalizeSubgraph(Map<String, dynamic>.from(raw), state: state),
        ]
      : <JsonMap>[];
  result['dataWires'] = result['dataWires'] is List
      ? result['dataWires']
      : <JsonMap>[];
  result['variableNodes'] = result['variableNodes'] is List
      ? result['variableNodes']
      : <JsonMap>[];
  result['triggerNodes'] = _normalizeTriggerNodes(result);

  // These fields belonged to the old sequence/trigger representation. Their
  // information is now represented by graph nodes and triggerNodes.
  for (final key in const [
    'sequence',
    'floatingSequences',
    'actions',
    'plugin',
    'trigger',
    'config',
    'stop',
  ]) {
    result.remove(key);
  }
  return result;
}

JsonMap _normalizeProfile(JsonMap input) {
  final result = Map<String, dynamic>.from(input);
  result['activationAutomation'] = _normalizeAutomation(
    _asMap(result['activationAutomation']),
    state: _MigrationState(),
  );
  result['deactivationAutomation'] = _normalizeAutomation(
    _asMap(result['deactivationAutomation']),
    state: _MigrationState(),
  );
  final rawTriggers = result['triggers'];
  if (rawTriggers is List) {
    result['triggers'] = [
      for (var index = 0; index < rawTriggers.length; index++)
        if (rawTriggers[index] is Map)
          _normalizeProfileTrigger(
            Map<String, dynamic>.from(rawTriggers[index] as Map),
            index,
          ),
    ];
  } else {
    result['triggers'] = <JsonMap>[];
  }
  return result;
}

JsonMap _normalizeProfileTrigger(JsonMap input, int index) {
  final result = Map<String, dynamic>.from(input);
  final automationSource = result['automation'] is Map
      ? _asMap(result['automation'])
      : {
          for (final key in const [
            'schemaVersion',
            'graph',
            'subgraphs',
            'dataWires',
            'variableNodes',
            'triggerNodes',
            'sequence',
            'floatingSequences',
            'actions',
          ])
            if (result.containsKey(key)) key: result[key],
        };
  result['id'] = result['id']?.toString().trim().isNotEmpty == true
      ? result['id'].toString()
      : 'trigger-$index';
  result['plugin'] = result['plugin']?.toString() ?? '';
  result['trigger'] = result['trigger']?.toString() ?? '';
  result['config'] = _asMap(result['config']);
  result['automation'] = _normalizeAutomation(
    automationSource,
    state: _MigrationState(),
  );
  return result;
}

JsonMap _normalizeStreamPlanSegment(JsonMap input) => {
  ...input,
  'activationAutomation': _normalizeAutomation(
    _asMap(input['activationAutomation']),
    state: _MigrationState(),
  ),
  'deactivationAutomation': _normalizeAutomation(
    _asMap(input['deactivationAutomation']),
    state: _MigrationState(),
  ),
};

JsonMap _normalizeSubgraph(JsonMap input, {required _MigrationState state}) {
  final result = Map<String, dynamic>.from(input);
  final graph = result['nodes'] is List
      ? _normalizeGraph(result, state: state)
      : _graphFromLegacy(result['sequence'] ?? result['actions'], state: state);
  result['nodes'] = graph['nodes'];
  result['edges'] = graph['edges'];
  result['entryNodeId'] = graph['entryNodeId'];
  result['parameters'] = result['parameters'] is List
      ? result['parameters']
      : <JsonMap>[];
  result['outputs'] = result['outputs'] is List
      ? result['outputs']
      : <JsonMap>[];
  result['dataWires'] = result['dataWires'] is List
      ? result['dataWires']
      : <JsonMap>[];
  result.remove('sequence');
  result.remove('actions');
  return result;
}

JsonMap _normalizeGraph(JsonMap input, {required _MigrationState state}) {
  final rawNodes = input['nodes'];
  final nodes = rawNodes is List
      ? [
          for (final raw in rawNodes.whereType<Map>())
            _normalizeGraphNode(Map<String, dynamic>.from(raw), state: state),
        ]
      : <JsonMap>[];
  final edges = input['edges'] is List ? input['edges'] : <JsonMap>[];
  final entry = input['entryNodeId']?.toString();
  return {
    'nodes': nodes,
    'edges': edges,
    'entryNodeId': entry?.isNotEmpty == true
        ? entry
        : nodes.firstOrNull?['id'] ?? '',
  };
}

JsonMap _normalizeGraphNode(JsonMap input, {required _MigrationState state}) {
  final result = Map<String, dynamic>.from(input);
  final plugin = result['plugin']?.toString();
  final action = result['action']?.toString();
  if ((result['type'] == null || result['type'] == 'action') &&
      plugin?.isNotEmpty == true &&
      action?.isNotEmpty == true) {
    result['type'] = 'action';
    result['config'] = _asMap(result['config']);
    state.actionCount++;
  }
  result['id'] = result['id']?.toString() ?? '';
  result['type'] = result['type']?.toString() ?? 'action';
  result['x'] = result['x'] is num ? result['x'] : 0;
  result['y'] = result['y'] is num ? result['y'] : 0;
  return result;
}

JsonMap _graphFromLegacy(Object? raw, {required _MigrationState state}) {
  final actions = raw is Map
      ? raw['actions']
      : raw is List
      ? raw
      : null;
  if (actions is! List) {
    return const {
      'nodes': <JsonMap>[],
      'edges': <JsonMap>[],
      'entryNodeId': '',
    };
  }

  final nodes = <JsonMap>[];
  final edges = <JsonMap>[];
  final usedIds = <String>{};
  String? previous;
  var index = 0;

  void append(Object? rawAction, int depth) {
    if (rawAction is! Map) return;
    final action = Map<String, dynamic>.from(rawAction);
    final stack = action['stack'];
    if (stack is List) {
      for (final child in stack) {
        append(child, depth + 1);
      }
    } else {
      final plugin = action['plugin']?.toString();
      final actionId = action['action']?.toString();
      if (plugin?.isNotEmpty == true && actionId?.isNotEmpty == true) {
        final requestedId = action['id']?.toString().trim();
        var id = requestedId?.isNotEmpty == true
            ? requestedId!
            : 'action-$index';
        while (!usedIds.add(id)) {
          id = '$id-$index';
        }
        final node = <String, dynamic>{
          'id': id,
          'type': 'action',
          'plugin': plugin,
          'action': actionId,
          'config': _asMap(action['config']),
          'x': action['x'] is num ? action['x'] : 320 + index * 285,
          'y': action['y'] is num ? action['y'] : 120 + depth * 128,
        };
        if (action['resultMapping'] is Map) {
          node['resultMapping'] = Map<String, dynamic>.from(
            action['resultMapping'] as Map,
          );
        }
        nodes.add(node);
        state.actionCount++;
        if (previous != null) {
          edges.add({'id': '$previous->$id', 'from': previous, 'to': id});
        }
        previous = id;
        index++;
      } else {
        state.warnings.add('Skipped a legacy action without plugin/action id.');
      }
      for (final key in const ['offsets', 'subFlows']) {
        final groups = action[key];
        if (groups is List) {
          for (final group in groups.whereType<Map>()) {
            final nested = group['actions'];
            if (nested is List) {
              for (final child in nested) {
                append(child, depth + 1);
              }
            }
          }
        }
      }
    }
  }

  for (final action in actions) {
    append(action, 0);
  }
  return {
    'nodes': nodes,
    'edges': edges,
    'entryNodeId': nodes.firstOrNull?['id'] ?? '',
  };
}

List<JsonMap> _normalizeTriggerNodes(JsonMap source) {
  final raw = source['triggerNodes'];
  if (raw is List) {
    return [
      for (final item in raw.whereType<Map>())
        if (item['id']?.toString().trim().isNotEmpty == true)
          {
            ...Map<String, dynamic>.from(item),
            'id': item['id'].toString(),
            'config': _asMap(item['config']),
            'x': item['x'] is num ? item['x'] : 42,
            'y': item['y'] is num ? item['y'] : 88,
          },
    ];
  }
  final plugin = source['plugin']?.toString();
  final trigger = source['trigger']?.toString();
  if (plugin?.isNotEmpty != true && trigger?.isNotEmpty != true) {
    return const <JsonMap>[];
  }
  return [
    {
      'id': 'trigger',
      'plugin': plugin,
      'trigger': trigger,
      'config': _asMap(source['config']),
      'stop': source['stop'] == true,
      'x': 42,
      'y': 88,
    },
  ];
}

JsonMap _asMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

int _countActions(Object? graph) => graph is Map && graph['nodes'] is List
    ? (graph['nodes'] as List)
          .whereType<Map>()
          .where((node) => node['type'] == 'action')
          .length
    : 0;

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

Future<JsonMap> readStructuredMap(File file) async {
  final contents = await file.readAsString();
  dynamic decoded;
  try {
    decoded = jsonDecode(contents);
  } on FormatException {
    decoded = _yamlToDart(loadYaml(contents));
  }
  if (decoded is! Map) {
    throw const FormatException('Persisted document must contain an object.');
  }
  return Map<String, dynamic>.from(decoded);
}

Future<File> backupOriginalFile(File file, {Directory? backupRoot}) async {
  if (!await file.exists()) {
    throw const FileSystemException('Cannot back up a missing document.');
  }
  final root = backupRoot ?? Directory(file.parent.parent.path);
  final backups = Directory('${root.path}/backup');
  await backups.create(recursive: true);
  final stamp = _backupStamp(DateTime.now());
  var directory = Directory('${backups.path}/$stamp');
  var suffix = 1;
  while (await directory.exists()) {
    directory = Directory('${backups.path}/$stamp-$suffix');
    suffix++;
  }
  await directory.create(recursive: true);
  return file.copy('${directory.path}/${file.uri.pathSegments.last}');
}

String _backupStamp(DateTime value) {
  String two(int item) => item.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}-'
      '${two(value.hour)}${two(value.minute)}${two(value.second)}'
      '-${value.millisecond.toString().padLeft(3, '0')}';
}

dynamic _yamlToDart(dynamic value) {
  if (value is YamlMap) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _yamlToDart(entry.value),
    };
  }
  if (value is YamlList) return value.map(_yamlToDart).toList();
  return value;
}
