import '../../../../schema/json.dart';
import '../../../../components/data_inputs/resource_field_values.dart';

abstract final class DashboardEditorValues {
  static int _idCounter = 0;

  static String newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}';

  static String _id(Object? value, String prefix) {
    final id = value?.toString().trim();
    return id == null || id.isEmpty ? newId(prefix) : id;
  }

  static String _value(Object? value, String fallback) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? fallback : text;
  }

  static JsonMap widget(Map value) {
    final size = value['size'] is Map
        ? Map<String, dynamic>.from(value['size'] as Map)
        : const <String, dynamic>{};
    final config = value['config'] is Map
        ? Map<String, dynamic>.from(value['config'] as Map)
        : <String, dynamic>{
            'label': value['title']?.toString() ?? 'New widget',
            'color': '#000000',
          };
    return {
      ...Map<String, dynamic>.from(value),
      'id': _id(value['id'], 'widget'),
      'plugin': _value(value['plugin'], 'dashboards'),
      'widget': _value(value['widget'], 'label'),
      'size': {
        'width': (size['width'] as num?)?.toInt() ?? 4,
        'height': (size['height'] as num?)?.toInt() ?? 1,
      },
      'config': config,
    };
  }

  static JsonMap section(Map value) {
    final widgets = ResourceFieldValues.maps(
      value['widgets'],
    ).map(widget).toList();
    return {
      ...Map<String, dynamic>.from(value),
      'id': _id(value['id'], 'section'),
      'name': value['name']?.toString() ?? 'New section',
      'columns': (value['columns'] as num?)?.toInt() ?? 4,
      'widgets': widgets,
    };
  }

  static JsonMap page(Map value) {
    final sections = ResourceFieldValues.maps(
      value['sections'],
    ).map(section).toList();
    return {
      ...Map<String, dynamic>.from(value),
      'id': _id(value['id'], 'page'),
      'name': value['name']?.toString() ?? 'New page',
      'sections': sections,
    };
  }
}
