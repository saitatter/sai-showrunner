/// Public trace facade. Domain types, bounded retention and projection inputs
/// remain independent from Flutter and persisted authoring documents.
library;

export 'trace/trace_models.dart';
export 'trace/trace_events.dart';
export 'trace/trace_snapshots.dart';
export 'trace/trace_sink.dart';
export 'trace/trace_session.dart';
export 'trace/trace_service.dart';
export 'trace/trace_redaction.dart'
    show SanitizedExecutionResult, sanitizeExecutionResult;
