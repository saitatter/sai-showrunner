import 'dart:convert';
import '../../schema/data_input.dart';
import '../../schema/json.dart';
import '../../services/structured_logger.dart';

/// Public usage previews are schema-aware; unavailable definitions hide values.
String safePluginConfigPreview(
  JsonMap config,
  Iterable<DartDataInputSchema> schemas,
) {
  final secretKey = RegExp(
    r'token|secret|password|authorization|api.?key|webhook|credential',
    caseSensitive: false,
  );
  Object? redact(
    Object? value,
    List<DartDataInputSchema> definitions, [
    String key = '',
  ]) {
    if (secretKey.hasMatch(key) || definitions.any((field) => field.secret)) {
      return '[redacted]';
    }
    if (value is Map) {
      return <String, Object?>{
        for (final entry in value.entries)
          entry.key.toString(): redact(entry.value, [
            for (final schema in definitions)
              for (final field in schema.fields)
                if ((field.key ?? field.label) == entry.key.toString()) field,
          ], entry.key.toString()),
      };
    }
    if (definitions.isEmpty) return '[redacted]';
    if (value is List) {
      return [
        for (final item in value)
          redact(item, [
            for (final schema in definitions)
              if (schema.itemSchema != null) schema.itemSchema!,
          ]),
      ];
    }
    if (value is String) {
      var text = ShowRunnerLogger.instance.redactText(value);
      text = text.replaceAll(RegExp(r'://[^/@\s]+@'), '://[redacted]@');
      final uri = Uri.tryParse(text);
      if (uri != null &&
          uri.hasScheme &&
          uri.hasQuery &&
          uri.queryParameters.keys.any(secretKey.hasMatch)) {
        text = uri
            .replace(
              queryParameters: {
                for (final entry in uri.queryParameters.entries)
                  entry.key: secretKey.hasMatch(entry.key)
                      ? '[redacted]'
                      : entry.value,
              },
            )
            .toString();
      }
      return text;
    }
    return value;
  }

  return const JsonEncoder.withIndent(
    '  ',
  ).convert(redact(config, schemas.toList()));
}
