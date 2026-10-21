import 'package:showrunner_flutter/persistence/document_revision.dart';
import 'package:showrunner_flutter/persistence/filesystem/file_transaction.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/viewer_data_repository.dart';
import 'package:showrunner_flutter/schema/viewer_data.dart';

const definitions = [
  ViewerVariableDefinition(name: 'points', type: 'Number', defaultValue: 5),
  ViewerVariableDefinition(
    name: 'groups',
    type: 'Array',
    defaultValue: <String>[],
  ),
  ViewerVariableDefinition(name: 'optional', type: 'String', required: false),
];
const viewer = ViewerIdentity(id: 'unicode/cont ñ', displayName: 'Viewer');

void main() {
  for (final adapter in ['file', 'memory']) {
    group(adapter, () {
      late Directory root;
      late ViewerDataRepository repository;
      ViewerDataRepository owner() =>
          adapter == 'file' ? FileViewerDataRepository(root) : repository;
      setUp(() async {
        root = await Directory.systemTemp.createTemp(
          'showrunner-viewer-contract-',
        );
        repository = adapter == 'file'
            ? FileViewerDataRepository(root)
            : InMemoryViewerDataRepository();
        await repository.saveDefinitions(definitions);
      });
      tearDown(() => root.delete(recursive: true));

      test(
        'stale schema edits cannot replace a newer definition set',
        () async {
          final revision = DocumentRevision.of(
            (await repository.loadDefinitions())
                .map((d) => d.toJson())
                .toList(),
          );
          await owner().saveDefinitions([
            ...definitions,
            const ViewerVariableDefinition(name: 'new', type: 'Boolean'),
          ]);
          await expectLater(
            repository.saveDefinitions(definitions, expectedRevision: revision),
            throwsA(isA<PersistenceConflictException>()),
          );
          expect((await repository.loadDefinitions()).last.name, 'new');
        },
      );
      test('an explicitly saved empty definition list round-trips', () async {
        await repository.saveDefinitions([]);
        expect(await repository.loadDefinitions(), isEmpty);
        expect(await repository.getDefaultViewerData(), isEmpty);
      });

      test(
        'defaults and provider-qualified viewer identities have identical semantics',
        () async {
          final initial = await repository.loadViewer('twitch', viewer);
          expect(initial.persisted, isFalse);
          expect(initial.values, {'points': 5, 'groups': [], 'optional': null});
          await repository.setViewerValue('twitch', viewer, 'points', 42);
          expect(
            (await repository.loadViewer('youtube', viewer)).values['points'],
            5,
          );
          expect(
            (await repository.loadViewer('twitch', viewer)).values['points'],
            42,
          );
          expect(await repository.queryViewers('youtube'), isEmpty);
        },
      );

      test(
        'concurrent owner increments do not lose accepted updates',
        () async {
          await Future.wait(
            List.generate(
              30,
              (_) => owner().offsetViewerValue('twitch', viewer, 'points', 1),
            ),
          );
          expect(
            (await repository.loadViewer('twitch', viewer)).values['points'],
            35,
          );
        },
      );

      test(
        'identity synchronization preserves group membership and provider scope',
        () async {
          await repository.setViewerValue('twitch', viewer, 'groups', [
            'vip',
            'moderator',
          ]);
          final updated = await repository.syncViewerIdentity(
            'twitch',
            const ViewerIdentity(id: 'unicode/cont ñ', displayName: 'Renamed'),
          );
          expect(updated.created, isFalse);
          expect(updated.changed, isTrue);
          expect(updated.row.values['groups'], ['vip', 'moderator']);
          expect(
            (await repository.loadViewer('youtube', viewer)).values['groups'],
            [],
          );
          final repeated = await repository.syncViewerIdentity(
            'twitch',
            updated.row.viewer,
          );
          expect(repeated.changed, isFalse);
        },
      );

      test(
        'imports require explicit overwrite and retain declared defaults',
        () async {
          final row = ViewerDataRow(
            provider: 'twitch',
            viewer: viewer,
            values: {'points': 8},
          );
          expect(await repository.importViewerRow(row), isTrue);
          expect(
            await repository.importViewerRow(
              ViewerDataRow(
                provider: 'twitch',
                viewer: viewer,
                values: {'points': 99},
              ),
            ),
            isFalse,
          );
          expect(
            (await repository.loadViewer('twitch', viewer)).values['points'],
            8,
          );
          expect(
            await repository.importViewerRow(
              ViewerDataRow(
                provider: 'twitch',
                viewer: viewer,
                values: {'points': 10},
              ),
              overwrite: true,
            ),
            isTrue,
          );
          expect((await repository.loadViewer('twitch', viewer)).values, {
            'points': 10,
            'groups': [],
            'optional': null,
          });
        },
      );

      test('sorting and pagination preserve numeric order', () async {
        for (var i = 0; i < 3; i++) {
          await repository.setViewerValue(
            'twitch',
            ViewerIdentity(id: '$i', displayName: 'Viewer $i'),
            'points',
            i * 10,
          );
        }
        final page = await repository.queryViewers(
          'twitch',
          start: 1,
          end: 2,
          sortBy: 'points',
          descending: true,
        );
        expect(page.single.viewer.id, '1');
      });

      test(
        'invalid updates reject without blocking a subsequent valid update',
        () async {
          await expectLater(
            repository.offsetViewerValue(
              'twitch',
              viewer,
              'points',
              double.nan,
            ),
            throwsArgumentError,
          );
          await expectLater(
            repository.setViewerValue('twitch', viewer, 'points', 'invalid'),
            throwsArgumentError,
          );
          await repository.offsetViewerValue('twitch', viewer, 'points', 2);
          expect(
            (await repository.loadViewer('twitch', viewer)).values['points'],
            7,
          );
        },
      );
    });
  }

  group('file diagnostics', () {
    late Directory root;
    setUp(() async {
      root = await Directory.systemTemp.createTemp(
        'showrunner-viewer-invalid-',
      );
    });
    tearDown(() => root.delete(recursive: true));
    test(
      'malformed definitions fail visibly and cannot be overwritten',
      () async {
        final file = File('${root.path}/variables.yaml');
        const source =
            '- name: private-marker\n  type: future-unsupported-type\n';
        await file.writeAsString(source);
        final repository = FileViewerDataRepository(root);
        await expectLater(repository.loadDefinitions(), throwsFormatException);
        await expectLater(
          repository.saveDefinitions(definitions),
          throwsFormatException,
        );
        expect(await file.readAsString(), source);
      },
    );
    test(
      'corrupt rows are visible and parser diagnostics omit source values',
      () async {
        final repository = FileViewerDataRepository(root);
        await repository.saveDefinitions(definitions);
        final directory = await Directory('${root.path}/twitch').create();
        final name = base64Url
            .encode(utf8.encode(viewer.id))
            .replaceAll('=', '');
        final file = File('${directory.path}/$name.json');
        await file.writeAsString('{ private-marker');
        for (final read in [
          () => repository.loadViewer('twitch', viewer),
          () => repository.queryViewers('twitch'),
        ]) {
          try {
            await read();
            fail('corrupt row was accepted');
          } on FormatException catch (error) {
            expect(error.toString(), isNot(contains('private-marker')));
          }
        }
        expect(await file.readAsString(), '{ private-marker');
      },
    );
    test(
      'row identity mismatch is reported instead of entering another viewer scope',
      () async {
        final repository = FileViewerDataRepository(root);
        await repository.saveDefinitions(definitions);
        await repository.syncViewerIdentity('twitch', viewer);
        final file =
            (await Directory(
                  '${root.path}/twitch',
                ).list().where((e) => e is File).toList()).single
                as File;
        await file.writeAsString(
          jsonEncode(
            ViewerDataRow(
              provider: 'youtube',
              viewer: viewer,
              values: {},
            ).toJson(),
          ),
        );
        await expectLater(
          repository.queryViewers('twitch'),
          throwsFormatException,
        );
      },
    );
  });
}
