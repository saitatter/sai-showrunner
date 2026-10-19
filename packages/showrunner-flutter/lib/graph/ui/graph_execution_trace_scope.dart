import 'package:flutter/widgets.dart';
import '../../runtime/execution_trace.dart';
import '../runtime/graph_execution_engine.dart';

/// Application-owned runtime capabilities for nested graph workspaces.
class GraphExecutionTraceScope extends InheritedWidget {
  const GraphExecutionTraceScope({
    super.key,
    required this.service,
    this.engine,
    required super.child,
  });
  final ExecutionTraceService service;
  final GraphExecutionEngine? engine;
  static GraphExecutionTraceScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GraphExecutionTraceScope>();
  @override
  bool updateShouldNotify(GraphExecutionTraceScope oldWidget) =>
      oldWidget.service != service || oldWidget.engine != engine;
}
