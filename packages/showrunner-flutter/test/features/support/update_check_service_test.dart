import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/schema/automation.dart';
import 'package:showrunner_flutter/schema/update.dart';
import 'package:showrunner_flutter/services/update_check_service.dart';

void main() {
  test('maps a GitHub release and sanitizes markdown notes', () async {
    final service = UpdateCheckService(
      currentVersion: '1.0.0-beta1',
      fetcher: () async => {
        'tag_name': 'v1.1.0',
        'body':
            '**Important** [details](https://example.test/details)\n<script>x</script>',
        'html_url':
            'https://github.com/saitatter/sai-showrunner/releases/tag/v1.1.0',
        'published_at': '2026-09-01T10:00:00Z',
      },
    );

    final result = await service.check();

    expect(result.status, UpdateStatus.available);
    expect(result.currentVersion, '1.0.0-beta1');
    expect(result.latestVersion, '1.1.0');
    expect(result.hasUpdate, isTrue);
    expect(result.releaseNotes, 'Important details\nx');
    expect(result.downloadUrl, contains('/releases/tag/v1.1.0'));
    expect(result.releaseDate, '2026-09-01T10:00:00Z');
  });

  test('treats a v-prefixed current release as up to date', () async {
    final service = UpdateCheckService(
      currentVersion: 'v1.1.0',
      fetcher: () async => {'tag_name': '1.1.0', 'body': ''},
    );

    final result = await service.check();

    expect(result.status, UpdateStatus.upToDate);
    expect(result.hasUpdate, isFalse);
  });

  test('returns a useful offline error without throwing', () async {
    final service = UpdateCheckService(
      currentVersion: '1.0.0',
      fetcher: () async => throw const SocketException('offline'),
    );

    final result = await service.check();

    expect(result.status, UpdateStatus.error);
    expect(result.errorMessage, 'Update check is offline.');
  });

  test('returns a timeout error for a slow release source', () async {
    final service = UpdateCheckService(
      currentVersion: '1.0.0',
      timeout: const Duration(milliseconds: 1),
      fetcher: () async => Future<JsonMap>.delayed(
        const Duration(milliseconds: 20),
        () => {'tag_name': '1.1.0'},
      ),
    );

    final result = await service.check();

    expect(result.status, UpdateStatus.error);
    expect(result.errorMessage, 'Update check timed out.');
  });
}
