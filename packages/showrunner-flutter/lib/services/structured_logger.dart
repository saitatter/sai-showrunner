import 'dart:async';

import '../domain/errors/showrunner_error.dart';

enum LogLevel { debug, info, warning, error }

class LogEntry {
  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
    this.details,
    this.error,
    this.typedError,
  });

  final DateTime timestamp;
  final LogLevel level;
  final String category;
  final String message;
  final Map<String, dynamic>? details;
  final Object? error;
  final ShowRunnerError? typedError;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'timestamp': timestamp.toIso8601String(),
    'level': level.name,
    'category': category,
    'message': message,
    if (details != null) 'details': details,
    if (error != null) 'error': error.toString(),
    if (typedError != null) 'errorDetails': typedError!.toJson(),
  };
}

class ShowRunnerLogger {
  ShowRunnerLogger._();

  static final ShowRunnerLogger instance = ShowRunnerLogger._();

  final List<LogEntry> _logs = <LogEntry>[];
  final _controller = StreamController<LogEntry>.broadcast();
  int maxHistory = 500;

  List<LogEntry> get logs => List.unmodifiable(_logs);
  Stream<LogEntry> get stream => _controller.stream;

  void log(
    LogLevel level,
    String category,
    String message, {
    Map<String, dynamic>? details,
    Object? error,
    ShowRunnerError? typedError,
  }) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      category: category,
      message: message,
      details: details,
      error: error,
      typedError: typedError,
    );
    _logs.add(entry);
    if (_logs.length > maxHistory) {
      _logs.removeAt(0);
    }
    _controller.add(entry);
  }

  void debug(
    String category,
    String message, {
    Map<String, dynamic>? details,
  }) => log(LogLevel.debug, category, message, details: details);

  void info(String category, String message, {Map<String, dynamic>? details}) =>
      log(LogLevel.info, category, message, details: details);

  void warning(
    String category,
    String message, {
    Map<String, dynamic>? details,
  }) => log(LogLevel.warning, category, message, details: details);

  void error(
    String category,
    String message, {
    Map<String, dynamic>? details,
    Object? error,
  }) => log(LogLevel.error, category, message, details: details, error: error);

  void clear() {
    _logs.clear();
  }
}
