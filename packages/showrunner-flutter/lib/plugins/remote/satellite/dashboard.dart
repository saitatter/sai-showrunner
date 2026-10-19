part of '../satellite.dart';

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
    if (value is! Map) {
      throw const FormatException('Remote dashboard config must be an object.');
    }
    final pages = <RemoteDashboardPage>[];
    for (final raw in (value['pages'] as List?) ?? const []) {
      try {
        pages.add(RemoteDashboardPage.fromJson(raw));
      } on FormatException {
        // Keep valid pages visible when one remote widget is malformed.
      }
    }
    final slots = <RemoteResourceSlot>[];
    for (final raw in (value['resourceSlots'] as List?) ?? const []) {
      if (raw is! Map) continue;
      final id = raw['id']?.toString().trim() ?? '';
      final type = raw['slotType']?.toString().trim() ?? '';
      if (id.isEmpty || type.isEmpty) continue;
      slots.add(
        RemoteResourceSlot(
          id: id,
          name: raw['name']?.toString().trim().isNotEmpty == true
              ? raw['name'].toString()
              : id,
          resourceType: type,
        ),
      );
    }
    return RemoteDashboardConfig(
      name: value['name']?.toString().trim().isNotEmpty == true
          ? value['name'].toString()
          : 'Remote dashboard',
      pages: pages,
      resourceSlots: slots,
    );
  }
}

final class RemoteDashboardPage {
  const RemoteDashboardPage({
    required this.id,
    required this.name,
    required this.sections,
  });

  final String id;
  final String name;
  final List<RemoteDashboardSection> sections;

  factory RemoteDashboardPage.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Remote dashboard page must be an object.');
    }
    final id = value['id']?.toString().trim() ?? '';
    if (id.isEmpty) {
      throw const FormatException('Remote dashboard page has no ID.');
    }
    return RemoteDashboardPage(
      id: id,
      name: value['name']?.toString() ?? id,
      sections: [
        for (final raw in (value['sections'] as List?) ?? const [])
          if (raw is Map) RemoteDashboardSection.fromJson(raw),
      ],
    );
  }
}

final class RemoteDashboardSection {
  const RemoteDashboardSection({
    required this.id,
    required this.name,
    required this.columns,
    required this.widgets,
  });

  final String id;
  final String name;
  final int columns;
  final List<RemoteDashboardWidget> widgets;

  factory RemoteDashboardSection.fromJson(Map value) {
    final id = value['id']?.toString().trim() ?? '';
    if (id.isEmpty) {
      throw const FormatException('Remote dashboard section has no ID.');
    }
    return RemoteDashboardSection(
      id: id,
      name: value['name']?.toString() ?? id,
      columns: (value['columns'] as num?)?.toInt().clamp(1, 12) ?? 4,
      widgets: [
        for (final raw in (value['widgets'] as List?) ?? const [])
          if (raw is Map) RemoteDashboardWidget.fromJson(raw),
      ],
    );
  }
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

  final String id;
  final String plugin;
  final String widget;
  final int width;
  final int height;
  final SatelliteJson config;

  factory RemoteDashboardWidget.fromJson(Map value) {
    final id = value['id']?.toString().trim() ?? '';
    if (id.isEmpty) {
      throw const FormatException('Remote dashboard widget has no ID.');
    }
    final size = value['size'] is Map
        ? Map<String, dynamic>.from(value['size'] as Map)
        : const <String, dynamic>{};
    final config = value['config'] is Map
        ? Map<String, dynamic>.from(value['config'] as Map)
        : <String, dynamic>{};
    return RemoteDashboardWidget(
      id: id,
      plugin: value['plugin']?.toString() ?? '',
      widget: value['widget']?.toString() ?? '',
      width: ((size['width'] as num?)?.toInt() ?? 1).clamp(1, 12),
      height: ((size['height'] as num?)?.toInt() ?? 1).clamp(1, 12),
      config: config,
    );
  }
}
