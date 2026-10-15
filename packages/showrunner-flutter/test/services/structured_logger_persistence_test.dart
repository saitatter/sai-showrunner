import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/services/structured_logger.dart';

void main() {
  test(
    'persistent diagnostics redact secrets, retain stack traces and rotate',
    () async {
      final root = await Directory.systemTemp.createTemp('showrunner-logs-');
      final logger = ShowRunnerLogger.instance;
      await logger.initialize(root);
      try {
        logger.registerSecrets({'token': 'fixture-private-token'});
        logger.error(
          'test',
          'Bearer another-secret /?access_token=third-secret fixture-private-token',
          details: {
            'password': 'secret-password',
            'context': 'fixture-private-token',
          },
          error: StateError('fixture-private-token'),
          stackTrace: StackTrace.fromString(
            'fixture stack fixture-private-token',
          ),
        );
        await logger.flush();
        final file = File('${root.path}/showrunner.jsonl');
        final text = await file.readAsString();
        for (final secret in [
          'another-secret',
          'third-secret',
          'fixture-private-token',
          'secret-password',
        ]) {
          expect(text, isNot(contains(secret)));
        }
        final entry = jsonDecode(text.trim()) as Map;
        expect(entry['stackTrace'], contains('fixture stack'));
        await file.writeAsString('x' * (1024 * 1024));
        logger.info('test', 'after rotation');
        await logger.flush();
        expect(await File('${file.path}.1').exists(), isTrue);
        expect(await file.readAsString(), contains('after rotation'));
      } finally {
        // Keep the singleton pointed at a valid directory for later tests.
        await logger.initialize(
          Directory('${Directory.systemTemp.path}/showrunner-test-diagnostics'),
        );
        await root.delete(recursive: true);
      }
    },
  );
}
