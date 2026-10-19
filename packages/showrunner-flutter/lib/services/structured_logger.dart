import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
    this.stackTrace,
    this.safeErrorDetails,
  });

  final String? stackTrace;
  final Map<String, dynamic>? safeErrorDetails;
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
    if (stackTrace != null) 'stackTrace': stackTrace,
    if (safeErrorDetails != null) 'errorDetails': safeErrorDetails,
    if (typedError != null && safeErrorDetails == null)
      'errorDetails': typedError!.toJson(),
  };
}

class ShowRunnerLogger {
  ShowRunnerLogger._();

  static final ShowRunnerLogger instance = ShowRunnerLogger._();

  final List<LogEntry> _logs = <LogEntry>[];
  final _controller = StreamController<LogEntry>.broadcast();
  int maxHistory = 500;
  Directory? _directory;
  Future<void> _writes = Future<void>.value();
  final _secrets = <String>{};

  void registerSecrets(Object? value) {
    if (value is Map) {
      for (final item in value.values) {
        registerSecrets(item);
      }
    } else if (value is List) {
      for (final item in value) {
        registerSecrets(item);
      }
    } else if (value is String && value.length >= 4) {
      _secrets.add(value);
    }
  }

  String redactText(String text) {
    for (final secret in _secrets) {
      text = text.replaceAll(secret, '[redacted]');
    }
    return text
        .replaceAll(
          RegExp(r'Bearer\s+[^\s"\x27]+', caseSensitive: false),
          'Bearer [redacted]',
        )
        .replaceAllMapped(
          RegExp(
            r'(access_token|refresh_token|client_secret|api_key|password)=([^&\s]+)',
            caseSensitive: false,
          ),
          (match) => '${match[1]}=[redacted]',
        );
  }

  dynamic _sanitize(Object? value, [String key = '']) {
    if (RegExp(
      r'token|secret|password|authorization|api.?key|webhook',
      caseSensitive: false,
    ).hasMatch(key)) {
      return '[redacted]';
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): _sanitize(entry.value, entry.key.toString()),
      };
    }
    if (value is Iterable) return value.map((item) => _sanitize(item)).toList();
    if (value is String) return redactText(value);
    if (value == null || value is num || value is bool) return value;
    return redactText(value.toString());
  }

  Future<void> initialize(Directory directory) async {
    await flush();
    await directory.create(recursive: true);
    _directory = directory;
  }

  Future<void> flush() => _writes;

  void _persist(LogEntry entry) {
    final directory = _directory;
    if (directory == null) return;
    _writes = _writes
        .then((_) async {
          final file = File('${directory.path}/showrunner.jsonl');
          if (await file.exists() && await file.length() >= 1024 * 1024) {
            for (var index = 2; index >= 1; index--) {
              final source = File('${file.path}.$index');
              final target = File('${file.path}.${index + 1}');
              if (await source.exists()) {
                if (await target.exists()) await target.delete();
                await source.rename(target.path);
              }
            }
            final first = File('${file.path}.1');
            if (await first.exists()) await first.delete();
            await file.rename(first.path);
          }
          await file.writeAsString(
            '${jsonEncode(_sanitize(entry.toJson()))}\n',
            mode: FileMode.append,
            flush: true,
          );
        })
        .catchError((Object error) {
          stderr.writeln(
            'Could not persist ShowRunner diagnostics: ${redactText(error.toString())}',
          );
        });
  }

  List<LogEntry> get logs => List.unmodifiable(_logs);
  Stream<LogEntry> get stream => _controller.stream;

  void log(
    LogLevel level,
    String category,
    String message, {
    Map<String, dynamic>? details,
    Object? error,
    ShowRunnerError? typedError,
    StackTrace? stackTrace,
  }) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      category: category,
      message: redactText(message),
      details: details == null
          ? null
          : Map<String, dynamic>.from(_sanitize(details) as Map),
      error: error == null ? null : redactText(error.toString()),
      typedError: typedError,
      safeErrorDetails: typedError == null
          ? null
          : Map<String, dynamic>.from(_sanitize(typedError.toJson()) as Map),
      stackTrace: stackTrace == null ? null : redactText(stackTrace.toString()),
    );
    _logs.add(entry);
    if (_logs.length > maxHistory) {
      _logs.removeAt(0);
    }
    _controller.add(entry);
    _persist(entry);
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
    StackTrace? stackTrace,
  }) => log(
    LogLevel.error,
    category,
    message,
    details: details,
    error: error,
    stackTrace: stackTrace,
  );

  void clear() {
    _logs.clear();
  }
}
