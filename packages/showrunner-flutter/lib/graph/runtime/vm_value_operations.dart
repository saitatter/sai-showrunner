import 'automation_runtime_projection.dart';
import 'graph_program.dart';
import 'runtime_values.dart';
import '../../runtime/expression.dart';

// Pure VM value operations; the reference interpreter remains independent.
Map<String, List<({String toPort, DartGraphWireSource source})>>
vmBuildNodeWireInputs(DartGraphProgram program) {
  final result =
      <String, List<({String toPort, DartGraphWireSource source})>>{};
  for (final entry in program.wireMap.entries) {
    result.putIfAbsent(entry.key.nodeId, () => []).add((
      toPort: entry.key.portId,
      source: entry.value,
    ));
  }
  return result;
}

RuntimeMap? vmNormalizeActionResult(Object? result) {
  if (result is Map) {
    return {
      for (final entry in result.entries) entry.key.toString(): entry.value,
    };
  }
  return result == null ? null : {'_result': result};
}

Object? vmCloneValue(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): vmCloneValue(entry.value),
    };
  }
  if (value is List) return value.map(vmCloneValue).toList();
  return value;
}

void vmSetPath(RuntimeMap target, String path, Object? value) {
  final parts = path.split('.').where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) return;
  var current = target;
  for (final part in parts.take(parts.length - 1)) {
    final next = current[part];
    if (next is Map) {
      final copy = Map<String, dynamic>.from(next);
      current[part] = copy;
      current = copy;
    } else {
      current[part] = <String, dynamic>{};
      current = current[part] as RuntimeMap;
    }
  }
  current[parts.last] = value;
}

dynamic vmGetPath(dynamic source, String path) {
  if (source == null) return null;
  var current = source;
  for (final part in path.split('.').where((part) => part.isNotEmpty)) {
    if (current is Map) {
      current = current[part];
    } else if (current is List) {
      final index = int.tryParse(part);
      if (index == null || index < 0 || index >= current.length) return null;
      current = current[index];
    } else {
      return null;
    }
  }
  return current;
}

Map<String, dynamic> vmDefinitionOutputValues(
  List<JsonMap> definitions,
  EvaluationContext context,
) => {
  for (final definition in definitions)
    if (definition['name'] is String && definition['expression'] != null)
      definition['name'].toString(): evaluateRuntimeInput(
        definition['expression'],
        context,
      ),
};

num vmAsNumber(Object? value) =>
    value is num ? value : num.tryParse('$value') ?? double.nan;

bool vmTruthy(Object? value) => value is bool
    ? value
    : value != null && value != 0 && value != '' && value != false;
