import 'dart:convert';

import 'package:flutter/services.dart';

class GeneratedOverlayWidget {
  const GeneratedOverlayWidget({
    required this.pluginId,
    required this.id,
    required this.name,
    this.description,
    this.icon,
    required this.defaultSize,
    this.config = const <String, dynamic>{},
    this.capabilities = const <String, dynamic>{},
  });

  final String pluginId;
  final String id;
  final String name;
  final String? description;
  final String? icon;
  final Map<String, dynamic> defaultSize;
  final Map<String, dynamic> config;
  final Map<String, dynamic> capabilities;

  String get key => '$pluginId.$id';
}

class GeneratedOverlayWidgetCatalog {
  const GeneratedOverlayWidgetCatalog._();

  static const assetPath = 'assets/overlay_widgets.generated.json';

  static Future<List<GeneratedOverlayWidget>> load() async {
    final source = await rootBundle.loadString(assetPath);
    final document = jsonDecode(source) as Map<String, dynamic>;
    final plugins = document['plugins'] as List<dynamic>? ?? const [];
    return [
      for (final pluginValue in plugins)
        ..._widgetsFor(pluginValue as Map<String, dynamic>),
    ];
  }

  static Iterable<GeneratedOverlayWidget> _widgetsFor(
    Map<String, dynamic> plugin,
  ) sync* {
    final pluginId = plugin['pluginId']?.toString() ?? '';
    final widgets = plugin['widgets'] as List<dynamic>? ?? const [];
    for (final value in widgets) {
      final widget = Map<String, dynamic>.from(value as Map);
      yield GeneratedOverlayWidget(
        pluginId: pluginId,
        id: widget['id']?.toString() ?? '',
        name: widget['name']?.toString() ?? '',
        description: widget['description']?.toString(),
        icon: widget['icon']?.toString(),
        defaultSize: Map<String, dynamic>.from(
          (widget['defaultSize'] as Map?) ?? const <String, dynamic>{},
        ),
        config: Map<String, dynamic>.from(
          (widget['config'] as Map?) ?? const <String, dynamic>{},
        ),
        capabilities: Map<String, dynamic>.from(
          (widget['capabilities'] as Map?) ?? const <String, dynamic>{},
        ),
      );
    }
  }
}
