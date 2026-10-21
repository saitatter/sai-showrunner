import '../../../../schema/json.dart';
import '../../generated_widget_catalog.dart';

abstract final class OverlayWidgetPresentation {
  static String title(
    JsonMap widget, [
    List<GeneratedOverlayWidget> catalog = const [],
  ]) {
    final name = widget['name']?.toString().trim();
    if (name != null && name.isNotEmpty) return name;
    final config = widget['config'];
    if (config is Map &&
        config['label']?.toString().trim().isNotEmpty == true) {
      return config['label'].toString();
    }
    for (final definition in catalog) {
      if (definition.pluginId == pluginId(widget) &&
          definition.id == widgetId(widget)) {
        return definition.name;
      }
    }
    return widget['title']?.toString() ??
        widget['widget']?.toString() ??
        'Widget';
  }

  static String pluginId(JsonMap widget) => widget['plugin']?.toString() ?? '';

  static String widgetId(JsonMap widget) => widget['widget']?.toString() ?? '';
}
