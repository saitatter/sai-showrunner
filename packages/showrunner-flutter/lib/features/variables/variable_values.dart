import 'dart:convert';

String displayVariableValue(dynamic value) {
  if (value is Map || value is List) return jsonEncode(value);
  return value?.toString() ?? '';
}

dynamic parseVariableValue(String type, String value) {
  final trimmed = value.trim();
  if (type == 'number') return num.tryParse(trimmed) ?? 0;
  if (type == 'boolean') return trimmed.toLowerCase() == 'true';
  if (type == 'json' ||
      type == 'object' ||
      type == 'list' ||
      type == 'twitchviewer') {
    try {
      return jsonDecode(trimmed);
    } on FormatException {
      return trimmed;
    }
  }
  return value;
}
