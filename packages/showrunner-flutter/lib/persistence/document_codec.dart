import 'dart:convert';

import 'package:yaml/yaml.dart';

/// Preserves the document shape and escapes strings using YAML-compatible JSON.
String encodeYaml(Map<String, dynamic> value) {
  final lines = <String>[];
  void append(Object? node, int depth) {
    final indent = ' ' * depth;
    bool nested(Object? value) =>
        value is Map && value.isNotEmpty || value is List && value.isNotEmpty;
    if (node is Map) {
      for (final entry in node.entries) {
        final key = jsonEncode(entry.key.toString());
        lines.add(
          '$indent$key:${nested(entry.value) ? '' : ' ${jsonEncode(entry.value)}'}',
        );
        if (nested(entry.value)) append(entry.value, depth + 2);
      }
    } else if (node is List) {
      for (final item in node) {
        lines.add('$indent-${nested(item) ? '' : ' ${jsonEncode(item)}'}');
        if (nested(item)) append(item, depth + 2);
      }
    }
  }

  if (value.isEmpty) return '{}\n';
  append(value, 0);
  return '${lines.join('\n')}\n';
}

dynamic decodeYamlValue(dynamic value) {
  if (value is YamlMap) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): decodeYamlValue(entry.value),
    };
  }
  if (value is YamlList) return value.map(decodeYamlValue).toList();
  return value;
}
