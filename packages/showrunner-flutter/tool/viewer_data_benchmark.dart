import 'dart:convert';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'package:showrunner_flutter/persistence/filesystem/safe_path.dart';
import 'package:showrunner_flutter/persistence/sqlite_viewer_data_repository.dart';
import 'package:showrunner_flutter/schema/viewer_data.dart';

Future<void> main(List<String> args) async {
  final sizes = args.isEmpty
      ? [1000, 10000, 100000]
      : args.map(int.parse).toList();
  final scratch = await Directory.fromUri(
    Platform.script.resolve('../../../.tmp/viewer-benchmark/'),
  ).create(recursive: true);
  for (final size in sizes) {
    if (size < 1 || size > 1000000) {
      throw ArgumentError('Use 1..1000000 viewers.');
    }
    final root = await scratch.createTemp('$size-');
    final repository = SqliteViewerDataRepository(
      Directory('${root.path}/store'),
    );
    final second = SqliteViewerDataRepository(repository.directory);
    try {
      final archive = File('${root.path}/seed.ndjson');
      final sink = archive.openWrite();
      sink.writeln(
        jsonEncode({
          'format': 'showrunner.viewer-data',
          'version': 1,
          'definitions': [
            const ViewerVariableDefinition(
              name: 'points',
              type: 'Number',
            ).toJson(),
            const ViewerVariableDefinition(
              name: 'groups',
              type: 'Array',
            ).toJson(),
          ],
        }),
      );
      for (var i = 0; i < size; i++) {
        sink.writeln(
          jsonEncode({
            'viewer': {
              'provider': 'twitch',
              'id': '$i'.padLeft(7, '0'),
              'displayName': 'Viewer $i',
              'values': {'points': i % 997},
            },
          }),
        );
        if (i % 500 == 0) await sink.flush();
      }
      sink.writeln(jsonEncode({'complete': true, 'viewers': size}));
      await sink.close();
      final seed = Stopwatch()..start();
      final imported = await repository.importFrom(archive);
      seed.stop();
      if (imported != size) throw StateError('Incorrect seed count.');
      Future<Map<String, num>> measure(Future<void> Function() action) async {
        await action();
        final samples = <double>[];
        for (var i = 0; i < 30; i++) {
          final timer = Stopwatch()..start();
          await action();
          timer.stop();
          samples.add(timer.elapsedMicroseconds / 1000);
        }
        samples.sort();
        return {'median_ms': samples[15], 'p95_ms': samples[28]};
      }

      final first = await measure(() async {
        final rows = await repository.queryViewers(
          'twitch',
          sortBy: 'points',
          descending: true,
          end: 100,
        );
        if (rows.length != (size < 100 ? size : 100)) {
          throw StateError('Incorrect first page.');
        }
      });
      final last = await measure(() async {
        final rows = await repository.queryViewers(
          'twitch',
          sortBy: 'points',
          descending: true,
          start: size > 100 ? size - 100 : 0,
          end: size,
        );
        if (rows.isEmpty) throw StateError('Missing last page.');
      });
      const viewer = ViewerIdentity(id: '0000000', displayName: 'Viewer 0');
      final lookup = await measure(() async {
        await repository.loadViewer('twitch', viewer);
      });
      final update = await measure(() async {
        await repository.offsetViewerValue('twitch', viewer, 'points', 1);
      });
      await Future.wait(
        List.generate(
          100,
          (i) => (i.isEven ? repository : second).offsetViewerValue(
            'twitch',
            viewer,
            'points',
            1,
          ),
        ),
      );
      if ((await repository.loadViewer('twitch', viewer)).values['points'] !=
          131) {
        throw StateError('Lost concurrent writes.');
      }
      final inspect = sqlite3.open(
        '${repository.directory.path}/viewers.sqlite',
      );
      final plan = inspect.select(
        '''EXPLAIN QUERY PLAN SELECT viewer_id FROM viewer_values
        WHERE provider = 'twitch' AND variable_name = 'points'
        ORDER BY sort_rank DESC, sort_number DESC, sort_text DESC, id_sort DESC, viewer_id DESC LIMIT 100''',
      ).toString();
      inspect.close();
      if (!plan.contains('viewer_values_sort') ||
          plan.contains('TEMP B-TREE')) {
        throw StateError('Leaderboard did not use its index.');
      }
      stdout.writeln(
        jsonEncode({
          'viewers': size,
          'import_ms': seed.elapsedMilliseconds,
          'leaderboard_first_100': first,
          'leaderboard_last_100': last,
          'lookup': lookup,
          'increment': update,
          'concurrent_increments': 100,
          'index': 'viewer_values_sort',
        }),
      );
    } finally {
      await second.close();
      await repository.close();
      if (!pathIsWithin(scratch.absolute.path, root.absolute.path)) {
        throw StateError('Unexpected benchmark path.');
      }
      await root.delete(recursive: true);
    }
  }
}
