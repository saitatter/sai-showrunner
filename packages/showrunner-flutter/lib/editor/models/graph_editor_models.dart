enum GraphNodeExecutionStatus { running, success, error, aborted }

final class GraphNodeExecutionVisual {
  const GraphNodeExecutionVisual({
    required this.status,
    required this.startedAt,
    this.duration,
    this.error,
    this.invocationCount,
    this.selectedPort,
    this.lastIteration,
    this.subgraphId,
  });

  final GraphNodeExecutionStatus status;
  final DateTime startedAt;
  final Duration? duration;
  final String? error;
  final int? invocationCount;
  final String? selectedPort;
  final int? lastIteration;
  final String? subgraphId;
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
