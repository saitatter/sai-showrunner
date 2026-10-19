import 'dart:async';
import 'dart:isolate';

/// Runs user-authored expressions away from the UI and kills excessive backtracking.
Future<Map<String, dynamic>?> findChatRegex(
  String pattern,
  String text, {
  bool caseSensitive = false,
  Duration timeout = const Duration(milliseconds: 250),
}) async {
  if (pattern.length > 2048 || text.length > 4096) {
    throw const FormatException('Pattern or message exceeds the regex limit.');
  }
  final port = ReceivePort();
  Isolate? worker;
  try {
    worker = await Isolate.spawn(_find, (
      port.sendPort,
      pattern,
      text,
      caseSensitive,
    ));
    final result = await port.first.timeout(timeout);
    if (result == null) return null;
    final value = Map<String, dynamic>.from(result as Map);
    if (value['error'] != null) throw FormatException(value['error'] as String);
    return value;
  } on TimeoutException {
    throw TimeoutException(
      'Regex exceeded its time budget. Simplify the pattern.',
    );
  } finally {
    worker?.kill(priority: Isolate.immediate);
    port.close();
  }
}

void _find((SendPort, String, String, bool) request) {
  final (port, pattern, text, caseSensitive) = request;
  try {
    final match = RegExp(
      pattern,
      caseSensitive: caseSensitive,
    ).firstMatch(text);
    port.send(
      match == null
          ? null
          : {
              'start': match.start,
              'end': match.end,
              'groups': [
                for (var i = 0; i <= match.groupCount; i++) match.group(i),
              ],
              'named': {
                for (final name in match.groupNames)
                  name: match.namedGroup(name),
              },
            },
    );
  } catch (error) {
    port.send({'error': '$error'});
  }
}
