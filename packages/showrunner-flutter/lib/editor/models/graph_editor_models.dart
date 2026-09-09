import 'package:flutter/material.dart';

import '../../schema/automation.dart';

enum GraphNodeExecutionStatus { running, success, error }

final class GraphNodeExecutionVisual {
  const GraphNodeExecutionVisual({
    required this.status,
    required this.startedAt,
    this.duration,
    this.error,
  });

  final GraphNodeExecutionStatus status;
  final DateTime startedAt;
  final Duration? duration;
  final String? error;
}

enum GraphAlignmentAxis { vertical, horizontal }

final class GraphAlignmentGuide {
  const GraphAlignmentGuide({
    required this.axis,
    required this.position,
    required this.from,
    required this.to,
  });

  final GraphAlignmentAxis axis;
  final double position;
  final double from;
  final double to;
}

final class GraphFrame {
  const GraphFrame({
    this.id = '',
    required this.title,
    required this.bounds,
    this.color = '#64b5f6',
    this.nodeIds = const [],
  });

  final String id;
  final String title;
  final Rect bounds;
  final String color;
  final List<String> nodeIds;

  GraphFrame copyWith({
    String? id,
    String? title,
    Rect? bounds,
    String? color,
    List<String>? nodeIds,
  }) => GraphFrame(
    id: id ?? this.id,
    title: title ?? this.title,
    bounds: bounds ?? this.bounds,
    color: color ?? this.color,
    nodeIds: nodeIds ?? this.nodeIds,
  );

  JsonMap toJson() => {
    'id': id,
    'title': title,
    'label': title,
    'color': color,
    'nodeIds': nodeIds,
    'left': bounds.left,
    'top': bounds.top,
    'right': bounds.right,
    'bottom': bounds.bottom,
    'x': bounds.left,
    'y': bounds.top,
    'width': bounds.width,
    'height': bounds.height,
  };

  factory GraphFrame.fromJson(Map value, {String? fallbackId}) {
    final left = _number(value['left'] ?? value['x']);
    final top = _number(value['top'] ?? value['y']);
    final right = value['right'] is num
        ? _number(value['right'])
        : left + _number(value['width']);
    final bottom = value['bottom'] is num
        ? _number(value['bottom'])
        : top + _number(value['height']);
    return GraphFrame(
      id: value['id']?.toString() ?? fallbackId ?? '',
      title:
          value['title']?.toString() ?? value['label']?.toString() ?? 'Frame',
      color: value['color']?.toString() ?? '#64b5f6',
      nodeIds: value['nodeIds'] is List
          ? (value['nodeIds'] as List).map((id) => id.toString()).toList()
          : const [],
      bounds: Rect.fromLTRB(left, top, right, bottom),
    );
  }
}

double _number(Object? value) => value is num ? value.toDouble() : 0;
