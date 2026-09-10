import 'overlay_widget_catalog.dart';
import 'overlay_widget_catalog.generated.dart';

export 'overlay_widget_catalog.dart'
    show GeneratedOverlayWidget, overlayConfigSchema;

class GeneratedOverlayWidgetCatalog {
  const GeneratedOverlayWidgetCatalog._();

  static const assetPath = 'assets/overlay_widgets.generated.json';
  static const List<GeneratedOverlayWidget> widgets = generatedOverlayWidgets;

  /// Returns the catalog generated from the plugin package manifests.
  ///
  /// The JSON asset is kept as the language-neutral artifact, while the const
  /// Dart view avoids an asynchronous metadata gap when an editor is opened.
  static Future<List<GeneratedOverlayWidget>> load() async =>
      generatedOverlayWidgets;

  static Future<GeneratedOverlayWidget?> find(
    String pluginId,
    String widgetId,
  ) async {
    for (final widget in generatedOverlayWidgets) {
      if (widget.pluginId == pluginId && widget.id == widgetId) return widget;
    }
    return null;
  }
}
