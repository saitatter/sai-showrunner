import 'dart:convert';
import '../../../services/public_data_projection.dart';
import 'protocol.dart';
import 'resources.dart';

/// Public document carried inside the versioned, resource-scoped control envelope.
/// Sharing metadata, local bindings and unknown widget fields never cross the wire.
final class RemoteDashboardConfig {
  const RemoteDashboardConfig({
    required this.name,
    required this.pages,
    required this.resourceSlots,
  });
  final String name;
  final List<RemoteDashboardPage> pages;
  final List<RemoteResourceSlot> resourceSlots;

  factory RemoteDashboardConfig.fromJson(Object? value) {
    final object = _object(value);
    final budget = _DocumentBudget();
    final pages = _list(
      object['pages'],
      64,
    ).map((raw) => RemoteDashboardPage._fromJson(raw, budget)).toList();
    final slots = _list(object['resourceSlots'], 128).map((raw) {
      final slot = _object(raw);
      final id = _id(slot['id']);
      return RemoteResourceSlot(
        id: id,
        name: _text(slot['name'], id),
        resourceType: _id(slot['slotType']),
      );
    }).toList();
    final sections = pages.expand((page) => page.sections).toList();
    final widgets = sections.expand((section) => section.widgets).toList();
    if (sections.length > 256 ||
        widgets.length > 512 ||
        !_unique(pages.map((page) => page.id)) ||
        !_unique(sections.map((section) => section.id)) ||
        !_unique(widgets.map((widget) => widget.id)) ||
        !_unique(slots.map((slot) => slot.id))) {
      throw const FormatException('Remote dashboard document limit exceeded.');
    }
    final document = RemoteDashboardConfig(
      name: _text(object['name'], 'Remote dashboard'),
      pages: List.unmodifiable(pages),
      resourceSlots: List.unmodifiable(slots),
    );
    if (utf8.encode(jsonEncode(document.toJson())).length > 512 * 1024) {
      throw const FormatException('Remote dashboard document limit exceeded.');
    }
    return document;
  }

  SatelliteJson toJson() => {
    'name': name,
    'pages': [for (final page in pages) page.toJson()],
    'resourceSlots': [
      for (final slot in resourceSlots)
        {'id': slot.id, 'name': slot.name, 'slotType': slot.resourceType},
    ],
  };
}

final class RemoteDashboardPage {
  const RemoteDashboardPage({
    required this.id,
    required this.name,
    required this.sections,
  });
  final String id, name;
  final List<RemoteDashboardSection> sections;
  factory RemoteDashboardPage.fromJson(Object? value) =>
      RemoteDashboardPage._fromJson(value, _DocumentBudget());
  factory RemoteDashboardPage._fromJson(Object? value, _DocumentBudget budget) {
    final object = _object(value);
    final id = _id(object['id']);
    final sections = _list(object['sections'], 256);
    budget.admitSections(sections.length);
    return RemoteDashboardPage(
      id: id,
      name: _text(object['name'], id),
      sections: List.unmodifiable(
        sections.map(
          (raw) => RemoteDashboardSection._fromJson(_object(raw), budget),
        ),
      ),
    );
  }
  SatelliteJson toJson() => {
    'id': id,
    'name': name,
    'sections': [for (final section in sections) section.toJson()],
  };
}

final class RemoteDashboardSection {
  const RemoteDashboardSection({
    required this.id,
    required this.name,
    required this.columns,
    required this.widgets,
  });
  final String id, name;
  final int columns;
  final List<RemoteDashboardWidget> widgets;
  factory RemoteDashboardSection.fromJson(Map value) =>
      RemoteDashboardSection._fromJson(value, _DocumentBudget());
  factory RemoteDashboardSection._fromJson(Map value, _DocumentBudget budget) {
    final widgets = _list(value['widgets'], 512);
    budget.admitWidgets(widgets.length);
    final id = _id(value['id']);
    return RemoteDashboardSection(
      id: id,
      name: _text(value['name'], id),
      columns: _dimension(value['columns'], 4),
      widgets: List.unmodifiable(
        widgets.map((raw) => RemoteDashboardWidget.fromJson(_object(raw))),
      ),
    );
  }
  SatelliteJson toJson() => {
    'id': id,
    'name': name,
    'columns': columns,
    'widgets': [for (final widget in widgets) widget.toJson()],
  };
}

final class RemoteDashboardWidget {
  const RemoteDashboardWidget({
    required this.id,
    required this.plugin,
    required this.widget,
    required this.width,
    required this.height,
    required this.config,
  });
  final String id, plugin, widget;
  final int width, height;
  final SatelliteJson config;
  factory RemoteDashboardWidget.fromJson(Map value) {
    final id = _id(value['id']);
    final plugin = _id(value['plugin']), widget = _id(value['widget']);
    final size = value['size'] == null
        ? const <String, dynamic>{}
        : _object(value['size']);
    final rawConfig = value['config'] == null
        ? const <String, dynamic>{}
        : _object(value['config']);
    final fields = switch ((plugin, widget)) {
      ('remote', 'button') => const ['displayName', 'triggerName', 'color'],
      ('dashboards', 'label') => const ['label', 'color'],
      _ => const <String>[],
    };
    final config = <String, dynamic>{};
    for (final field in fields) {
      if (rawConfig.containsKey(field)) {
        config[field] = _text(rawConfig[field], '');
      }
    }
    return RemoteDashboardWidget(
      id: id,
      plugin: plugin,
      widget: widget,
      width: _dimension(size['width'], 1),
      height: _dimension(size['height'], 1),
      config: Map.unmodifiable(config),
    );
  }
  SatelliteJson toJson() => {
    'id': id,
    'plugin': plugin,
    'widget': widget,
    'size': {'width': width, 'height': height},
    'config': config,
  };
}

Map _object(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('Invalid remote dashboard object.');
  }
  return value;
}

List _list(Object? value, int limit) {
  if (value == null) return const [];
  if (value is! List || value.length > limit) {
    throw const FormatException('Invalid remote dashboard collection.');
  }
  return value;
}

String _id(Object? value) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.length > 128 ||
      value.contains('\u0000')) {
    throw const FormatException('Invalid remote dashboard identifier.');
  }
  return value;
}

String _text(Object? value, String fallback) {
  if (value == null) return fallback;
  if (value is! String || value.length > 4096) {
    throw const FormatException('Invalid remote dashboard text.');
  }
  return projectPublicValue(value) as String? ?? '';
}

int _dimension(Object? value, int fallback) {
  if (value == null) return fallback;
  if (value is! num || !value.isFinite || value != value.toInt()) {
    throw const FormatException('Invalid remote dashboard dimension.');
  }
  return value.toInt().clamp(1, 12);
}

bool _unique(Iterable<String> values) => values.toSet().length == values.length;

final class _DocumentBudget {
  int sections = 0, widgets = 0;
  void admitSections(int count) {
    if ((sections += count) > 256) {
      throw const FormatException('Remote dashboard section limit exceeded.');
    }
  }

  void admitWidgets(int count) {
    if ((widgets += count) > 512) {
      throw const FormatException('Remote dashboard widget limit exceeded.');
    }
  }
}
