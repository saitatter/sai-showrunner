import 'dart:async';
import 'dart:io';

import 'package:showrunner_flutter/media/domain/media_file.dart';
import 'package:showrunner_flutter/media/scanner/media_library_service.dart';

Future<void> main(List<String> args) async {
  final fileCount = _readIntOption(args, 'files') ?? 1000;
  if (fileCount < 1) {
    throw ArgumentError.value(fileCount, 'files', 'must be greater than zero');
  }

  final root = await Directory.systemTemp.createTemp(
    'showrunner-media-benchmark-',
  );
  try {
    for (var index = 0; index < fileCount; index++) {
      final file = File(
        '${root.path}/media/folder-${index % 10}/sample-$index.mp3',
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(const <int>[0, 1, 2, 3], flush: false);
    }

    final service = MediaLibraryService(root);
    final first = await _timed(service.scan);
    final second = await _timed(service.scan);
    _printResult('first scan', first);
    _printResult('unchanged quick scan', second);
    if (second.result.stats.metadataReads != 0) {
      throw StateError(
        'Quick scan read metadata for unchanged files: '
        '${second.result.stats.metadataReads}',
      );
    }
    stdout.writeln(
      'media scan benchmark: files=$fileCount '
      'firstMs=${first.elapsed.inMilliseconds} '
      'unchangedMs=${second.elapsed.inMilliseconds}',
    );
  } finally {
    await root.delete(recursive: true);
  }
}

Future<({MediaScanResult result, Duration elapsed})> _timed(
  Future<MediaScanResult> Function() operation,
) async {
  final stopwatch = Stopwatch()..start();
  final result = await operation();
  stopwatch.stop();
  return (result: result, elapsed: stopwatch.elapsed);
}

void _printResult(
  String label,
  ({MediaScanResult result, Duration elapsed}) measured,
) {
  final stats = measured.result.stats;
  stdout.writeln(
    '$label: ${measured.elapsed.inMilliseconds}ms '
    'enumerated=${stats.enumerated} '
    'added=${stats.added} '
    'changed=${stats.changed} '
    'unchanged=${stats.unchanged} '
    'metadataReads=${stats.metadataReads}',
  );
}

int? _readIntOption(List<String> args, String name) {
  final prefix = '--$name=';
  final value = args
      .where((argument) => argument.startsWith(prefix))
      .map((argument) => argument.substring(prefix.length))
      .firstOrNull;
  return value == null ? null : int.tryParse(value);
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
