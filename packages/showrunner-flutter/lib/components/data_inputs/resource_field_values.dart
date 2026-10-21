import 'dart:convert';
import '../../schema/json.dart';

abstract final class ResourceFieldValues {
  static List<JsonMap> maps(Object? value) => value is List
      ? value
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
      : <JsonMap>[];

  static void moveListItem<T>(List<T> items, int from, int to) {
    if (from < 0 || from >= items.length || to < 0 || to >= items.length) {
      return;
    }
    final item = items.removeAt(from);
    items.insert(to, item);
  }

  static List<String> strings(Object? value) => value is List
      ? value.map((item) => item.toString()).toList()
      : <String>[];

  static String display(dynamic value) {
    if (value is List) return value.join(', ');
    return value?.toString() ?? '';
  }

  static String jsonDisplay(dynamic value) {
    if (value is Map) return jsonEncode(value);
    return display(value);
  }

  static dynamic parseJsonMap(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(trimmed);
      return decoded is Map<String, dynamic> ? decoded : trimmed;
    } on FormatException {
      return trimmed;
    }
  }
}
