import '../../plugins/registry/plugin_registry.dart';

String encodePluginSettingValue(Object? value) => value?.toString() ?? '';

dynamic decodePluginSettingValue(
  DartSettingContract definition,
  String rawValue,
) {
  if (definition.valueType == DartSettingType.boolean) {
    return decodePluginSettingBoolean(rawValue) ??
        definition.defaultValue ??
        false;
  }
  if (definition.valueType == DartSettingType.number) {
    final parsed = definition.defaultValue is int
        ? int.tryParse(rawValue)
        : double.tryParse(rawValue);
    if (parsed == null || !parsed.isFinite) {
      throw FormatException(
        '${definition.displayName} must be a valid number.',
      );
    }
    return parsed;
  }
  return rawValue;
}

bool? decodePluginSettingBoolean(String rawValue) {
  switch (rawValue.trim().toLowerCase()) {
    case 'true':
    case '1':
    case 'yes':
    case 'on':
      return true;
    case 'false':
    case '0':
    case 'no':
    case 'off':
      return false;
    default:
      return null;
  }
}
