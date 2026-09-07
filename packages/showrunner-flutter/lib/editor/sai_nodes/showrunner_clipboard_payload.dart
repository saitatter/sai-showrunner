import '../../schema/automation.dart';

/// ShowRunner-owned metadata that travels alongside a `sai_nodes` payload.
///
/// The graph package owns clipboard transport and node IDs. ShowRunner keeps
/// only the domain metadata that cannot be reconstructed from a generic node:
/// plugin configuration, variable/trigger markers, and custom titles.
final class ShowRunnerClipboardSnapshot {
  const ShowRunnerClipboardSnapshot({
    required this.nodeType,
    required this.data,
    this.title,
    this.isVariable = false,
    this.isTrigger = false,
  });

  final String nodeType;
  final JsonMap data;
  final String? title;
  final bool isVariable;
  final bool isTrigger;

  JsonMap toJson() => {
    'nodeType': nodeType,
    'data': _cloneJsonMap(data),
    if (title != null) 'title': title,
    'isVariable': isVariable,
    'isTrigger': isTrigger,
  };

  static ShowRunnerClipboardSnapshot? fromJson(dynamic value) {
    if (value is! Map) return null;
    final nodeType = value['nodeType'];
    final data = value['data'];
    if (nodeType is! String || data is! Map) return null;

    final title = value['title'];
    return ShowRunnerClipboardSnapshot(
      nodeType: nodeType,
      data: _cloneJsonMap(data),
      title: title is String ? title : null,
      isVariable: value['isVariable'] == true,
      isTrigger: value['isTrigger'] == true,
    );
  }
}

JsonMap _cloneJsonMap(Map<dynamic, dynamic> source) => {
  for (final entry in source.entries)
    entry.key.toString(): _cloneJsonValue(entry.value),
};

dynamic _cloneJsonValue(dynamic value) {
  if (value is Map) return _cloneJsonMap(value);
  if (value is List) return value.map(_cloneJsonValue).toList();
  return value;
}
