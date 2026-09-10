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
