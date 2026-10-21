import '../support/transaction_file_fixtures.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/persistence/filesystem/file_transaction.dart';
import 'package:showrunner_flutter/persistence/filesystem/safe_path.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp(
      'showrunner-file-transaction-',
    );
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  FileTransaction transaction([
    TransactionFileOperations operations = const TransactionFileOperations(),
  ]) => FileTransaction(
    directory: root,
    id: 'fixture',
    operations: operations,
    targets: {
      for (final name in ['a', 'b', 'c'])
        name: () => containedFile(root, ['$name.json']),
    },
  );
  Future<void> seed() async {
    for (final name in ['a', 'b', 'c']) {
      await File('${root.path}/$name.json').writeAsString('old-$name');
    }
  }

  List<FileMutation> mutations() => [
    for (final name in ['a', 'b', 'c'])
      FileMutation.write(name, utf8.encode('new-$name')),
  ];

  for (var step = 1; step <= 4; step++) {
    for (final after in [false, true]) {
      test(
        'recovers write step $step after=$after without mixed generations',
        () async {
          await seed();
          final failing = transaction(
            FaultInjectingFiles(writeAt: step, after: after),
          );
          await expectLater(
            failing.locked(() => failing.commit(mutations())),
            throwsA(isA<FileSystemException>()),
          );
          final recovery = transaction();
          await recovery.locked(recovery.recover);
          final expected = step == 1 && !after ? 'old' : 'new';
          for (final name in ['a', 'b', 'c']) {
            expect(
              await File('${root.path}/$name.json').readAsString(),
              '$expected-$name',
            );
          }
          expect(
            await File('${root.path}/.transactions/fixture.json').exists(),
            false,
          );
        },
      );
    }
  }
  for (var step = 1; step <= 4; step++) {
    test('resumes interrupted deletion at step $step', () async {
      await seed();
      final failing = transaction(
        FaultInjectingFiles(removeAt: step, after: false),
      );
      await expectLater(
        failing.locked(
          () => failing.commit([
            for (final name in ['a', 'b', 'c']) FileMutation.remove(name),
          ]),
        ),
        throwsA(isA<FileSystemException>()),
      );
      final recovery = transaction();
      await recovery.locked(recovery.recover);
      for (final name in ['a', 'b', 'c']) {
        expect(await File('${root.path}/$name.json').exists(), false);
      }
    });
  }
  test(
    'recovery preflights every target before applying any remaining write',
    () async {
      await seed();
      final failing = transaction(FaultInjectingFiles(writeAt: 3));
      await expectLater(
        failing.locked(() => failing.commit(mutations())),
        throwsA(isA<FileSystemException>()),
      );
      await File('${root.path}/c.json').writeAsString('external-change');
      final recovery = transaction();
      await expectLater(
        recovery.locked(recovery.recover),
        throwsA(isA<PersistenceConflictException>()),
      );
      expect(await File('${root.path}/b.json').readAsString(), 'old-b');
      expect(
        await File('${root.path}/c.json').readAsString(),
        'external-change',
      );
      expect(
        await File('${root.path}/.transactions/fixture.json').exists(),
        true,
      );
    },
  );
  for (final corrupt in ['version', 'target', 'checksum', 'missing-field']) {
    test(
      'preserves unsupported or corrupted $corrupt journals and all documents',
      () async {
        await seed();
        final failing = transaction(
          FaultInjectingFiles(writeAt: 1, after: true),
        );
        await expectLater(
          failing.locked(() => failing.commit(mutations())),
          throwsA(isA<FileSystemException>()),
        );
        final journal = File('${root.path}/.transactions/fixture.json');
        final data = jsonDecode(await journal.readAsString()) as Map;
        if (corrupt == 'version') {
          data['version'] = 999;
        }
        if (corrupt == 'target') {
          (data['writes'] as List).first['target'] = '../outside';
        }
        if (corrupt == 'checksum') {
          (data['writes'] as List).first['data'] = base64Encode([1, 2, 3]);
        }
        if (corrupt == 'missing-field') {
          ((data['writes'] as List).first as Map).remove('before');
        }
        final source = jsonEncode(data);
        await journal.writeAsString(source);
        final recovery = transaction();
        await expectLater(
          recovery.locked(recovery.recover),
          throwsFormatException,
        );
        expect(await journal.readAsString(), source);
        for (final name in ['a', 'b', 'c']) {
          expect(
            await File('${root.path}/$name.json').readAsString(),
            'old-$name',
          );
        }
      },
    );
  }
  test(
    'separate owners serialize complete read modify write operations',
    () async {
      await File('${root.path}/a.json').writeAsString('0');
      await Future.wait([
        for (var i = 0; i < 20; i++)
          (() async {
            final owner = transaction();
            await owner.locked(() async {
              await owner.recover();
              final value = int.parse(
                await File('${root.path}/a.json').readAsString(),
              );
              await owner.commit([
                FileMutation.write('a', utf8.encode('${value + 1}')),
              ]);
            });
          })(),
      ]);
      expect(await File('${root.path}/a.json').readAsString(), '20');
    },
  );
  test(
    'a process crash releases its lock and a fresh owner recovers the full generation',
    () async {
      final result = await Process.run('dart', [
        'run',
        'test/support/transaction_process_fixture.dart',
        root.path,
        'crash',
      ], runInShell: Platform.isWindows);
      expect(result.exitCode, 73, reason: '${result.stdout}\n${result.stderr}');
      final owner = transaction();
      await owner.locked(owner.recover);
      expect(await File('${root.path}/a.json').readAsString(), 'new-a');
      expect(await File('${root.path}/b.json').readAsString(), 'new-b');
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
  test(
    'an independent process cannot acquire a held repository lock',
    () async {
      final hold = await Process.start('dart', [
        'run',
        'test/support/transaction_process_fixture.dart',
        root.path,
        'hold',
      ], runInShell: Platform.isWindows);
      final errors = utf8.decoder.bind(hold.stderr).join();
      addTearDown(() async {
        await hold.stdin.close();
        await hold.exitCode;
        await errors;
      });
      expect(
        await utf8.decoder
            .bind(hold.stdout)
            .transform(const LineSplitter())
            .first,
        'locked',
      );
      final probe = await Process.run('dart', [
        'run',
        'test/support/transaction_process_fixture.dart',
        root.path,
        'probe',
      ], runInShell: Platform.isWindows);
      expect(probe.exitCode, 0, reason: '${probe.stderr}');
      expect('${probe.stdout}'.trim(), 'blocked');
      hold.stdin.writeln('release');
      await hold.stdin.flush();
      expect(await hold.exitCode, 0);
      final released = await Process.run('dart', [
        'run',
        'test/support/transaction_process_fixture.dart',
        root.path,
        'probe',
      ], runInShell: Platform.isWindows);
      expect(released.exitCode, 0, reason: '${released.stderr}');
      expect('${released.stdout}'.trim(), 'acquired');
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
