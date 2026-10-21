import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/document_revision.dart';
import 'package:showrunner_flutter/persistence/filesystem/file_transaction.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/schema/resource.dart';

void main() {
  late Directory root;
  ResourceRepository owner() => ResourceRepository(root);
  const original = ResourceData(id: 'draft', config: {'name': 'Original'});
  const changed = ResourceData(id: 'draft', config: {'name': 'Changed'});
  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'showrunner-resource-conflict-',
    );
    await owner().save(original);
  });
  tearDown(() => root.delete(recursive: true));

  test(
    'semantic revisions ignore object key order, preserve list order and hide values',
    () {
      final revision = DocumentRevision.of({
        'secret': 'private-marker',
        'value': [1, 2],
      });
      expect(
        revision,
        DocumentRevision.of({
          'value': [1, 2],
          'secret': 'private-marker',
        }),
      );
      expect(
        revision,
        isNot(
          DocumentRevision.of({
            'secret': 'private-marker',
            'value': [2, 1],
          }),
        ),
      );
      expect(revision.toString(), isNot(contains('private-marker')));
    },
  );

  test('two stale saves cannot both replace the accepted generation', () async {
    final revision = DocumentRevision.of(original.toJson());
    final outcomes = await Future.wait(
      List.generate(2, (i) async {
        try {
          await owner().save(
            ResourceData(id: 'draft', config: {'name': 'Owner $i'}),
            expectedRevision: revision,
          );
          return true;
        } on PersistenceConflictException {
          return false;
        }
      }),
    );
    expect(outcomes.where((success) => success), hasLength(1));
    expect((await owner().load('draft'))!.name, startsWith('Owner '));
  });

  test('stale delete leaves newer data intact', () async {
    await owner().save(changed);
    await expectLater(
      owner().delete(
        'draft',
        expectedRevision: DocumentRevision.of(original.toJson()),
      ),
      throwsA(isA<PersistenceConflictException>()),
    );
    expect((await owner().load('draft'))!.name, 'Changed');
  });

  test(
    'save after another owner deletes cannot resurrect the stale resource',
    () async {
      await owner().delete('draft');
      await expectLater(
        owner().save(
          changed,
          expectedRevision: DocumentRevision.of(original.toJson()),
        ),
        throwsA(isA<PersistenceConflictException>()),
      );
      expect(await owner().load('draft'), isNull);
    },
  );

  test('new resource creation rejects a colliding identity', () async {
    await expectLater(
      owner().save(changed, requireAbsent: true),
      throwsA(isA<PersistenceConflictException>()),
    );
    expect((await owner().load('draft'))!.name, 'Original');
  });
}
