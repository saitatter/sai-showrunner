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

/// Reject recursive aliases before they can recurse in repositories or logs.
/// Shared non-recursive aliases retain their YAML values without migration.
dynamic decodeYamlValue(dynamic value) {
  final active = Set<Object>.identity();
  dynamic decode(dynamic node) {
    if (node is! YamlMap && node is! YamlList) return node;
    if (!active.add(node as Object)) {
      throw const FormatException('Recursive YAML aliases are unsupported.');
    }
    try {
      if (node is YamlMap) {
        return <String, dynamic>{
          for (final entry in node.entries)
            entry.key.toString(): decode(entry.value),
        };
      }
      return (node as YamlList).map(decode).toList();
    } finally {
      active.remove(node);
    }
  }

  return decode(value);
}
