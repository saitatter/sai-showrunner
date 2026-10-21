import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/automation_repository.dart';
import 'package:showrunner_flutter/persistence/profile_repository.dart';
import 'package:showrunner_flutter/persistence/queue_config_repository.dart';
import 'package:showrunner_flutter/persistence/document_revision.dart';
import 'package:showrunner_flutter/persistence/filesystem/file_transaction.dart';
import 'package:showrunner_flutter/graph/domain/automation_document.dart';
import 'package:showrunner_flutter/schema/profile.dart';
import 'package:showrunner_flutter/schema/queue.dart';

ShowRunnerProfile profile(String name) => ShowRunnerProfile(
  name: name,
  activationMode: 'toggle',
  triggers: [],
  activationCondition: {},
  activationAutomation: AutomationDocument.empty(),
  deactivationAutomation: AutomationDocument.empty(),
);

void main() {
  for (final kind in ['automation', 'profile', 'queue']) {
    group(kind, () {
      late Directory root;
      File file() => File('${root.path}/$kind.yaml');
      Future<Map<String, dynamic>?> read() async => switch (kind) {
        'automation' => (await AutomationRepository(file()).load())?.toJson(),
        'profile' => (await ProfileRepository(file()).load())?.toJson(),
        _ => (await QueueConfigRepository(root).load(file())).toJson(),
      };
      Future<void> write(
        String name, {
        DocumentRevision? expectedRevision,
        bool requireAbsent = false,
      }) => switch (kind) {
        'automation' => AutomationRepository(file()).save(
          AutomationDocument.empty().withMetadata({'name': name}),
          expectedRevision: expectedRevision,
          requireAbsent: requireAbsent,
        ),
        'profile' => ProfileRepository(file()).save(
          profile(name),
          expectedRevision: expectedRevision,
          requireAbsent: requireAbsent,
        ),
        _ => QueueConfigRepository(root).save(
          '$kind.yaml',
          QueueConfig(name: name),
          expectedRevision: expectedRevision,
          requireAbsent: requireAbsent,
        ),
      };
      Future<void> remove(DocumentRevision revision) => switch (kind) {
        'automation' => AutomationRepository(
          file(),
        ).delete(expectedRevision: revision),
        'profile' => ProfileRepository(
          file(),
        ).delete(expectedRevision: revision),
        _ => QueueConfigRepository(
          root,
        ).delete('$kind.yaml', expectedRevision: revision),
      };
      setUp(() async {
        root = await Directory.systemTemp.createTemp(
          'showrunner-authoring-contract-',
        );
        await write('Original');
      });
      tearDown(() => root.delete(recursive: true));

      test('independent owners reject concurrent stale replacements', () async {
        final revision = DocumentRevision.of(await read());
        final outcomes = await Future.wait(
          List.generate(2, (i) async {
            try {
              await write('Owner $i', expectedRevision: revision);
              return true;
            } on PersistenceConflictException {
              return false;
            }
          }),
        );
        expect(outcomes.where((success) => success), hasLength(1));
      });
      test('stale delete preserves the accepted newer document', () async {
        final revision = DocumentRevision.of(await read());
        await write('Newer');
        final bytes = await file().readAsBytes();
        await expectLater(
          remove(revision),
          throwsA(isA<PersistenceConflictException>()),
        );
        expect(await file().readAsBytes(), bytes);
      });
      test(
        'save versus delete accepts only one owner of a generation',
        () async {
          final revision = DocumentRevision.of(await read());
          Future<bool> attempt(Future<void> Function() operation) async {
            try {
              await operation();
              return true;
            } on PersistenceConflictException {
              return false;
            }
          }

          final outcomes = await Future.wait([
            attempt(() => write('Saved', expectedRevision: revision)),
            attempt(() => remove(revision)),
          ]);
          expect(outcomes.where((success) => success), hasLength(1));
        },
      );
      test(
        'unsupported bytes reject load, save and delete without rewrite',
        () async {
          const source = '- unsupported\n';
          await file().writeAsString(source);
          await expectLater(read(), throwsFormatException);
          await expectLater(write('Replacement'), throwsFormatException);
          await expectLater(
            remove(DocumentRevision.of({})),
            throwsFormatException,
          );
          expect(await file().readAsString(), source);
        },
      );
      test(
        'creation requires absence and does not replace a colliding file',
        () async {
          final bytes = await file().readAsBytes();
          await expectLater(
            write('Collision', requireAbsent: true),
            throwsA(isA<PersistenceConflictException>()),
          );
          expect(await file().readAsBytes(), bytes);
        },
      );
    });
  }

  test('profile save freezes mutable fields before waiting for IO', () async {
    final root = await Directory.systemTemp.createTemp(
      'showrunner-profile-snapshot-',
    );
    addTearDown(() => root.delete(recursive: true));
    final extra = <String, dynamic>{
      'nested': {'value': 'accepted'},
    };
    final original = profile('Profile');
    final repository = ProfileRepository(File('${root.path}/profile.yaml'));
    final saving = repository.save(
      ShowRunnerProfile(
        name: original.name,
        activationMode: original.activationMode,
        triggers: original.triggers,
        activationCondition: original.activationCondition,
        activationAutomation: original.activationAutomation,
        deactivationAutomation: original.deactivationAutomation,
        extra: extra,
      ),
    );
    (extra['nested'] as Map)['value'] = 'mutated';
    await saving;
    expect((await repository.load())!.extra['nested'], {'value': 'accepted'});
  });
}
