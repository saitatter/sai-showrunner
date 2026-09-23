import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/schema/automation.dart';
import 'package:showrunner_flutter/schema/update.dart';
import 'package:showrunner_flutter/services/update_check_service.dart';

void main() {
  test('maps a GitHub release and preserves safe markdown notes', () async {
    final service = UpdateCheckService(
      currentVersion: '1.0.0-beta1',
      fetcher: () async => {
        'tag_name': 'v1.1.0',
        'body':
            '**Important** [details](https://example.test/details)\n<script>x</script>',
        'html_url':
            'https://github.com/saitatter/sai-showrunner/releases/tag/v1.1.0',
        'published_at': '2026-09-01T10:00:00Z',
        'assets': [
          {
            'name': 'ShowRunner-Flutter-windows-1.1.0.zip',
            'browser_download_url':
                'https://example.test/downloads/showrunner.zip',
            'digest':
                'sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
          },
        ],
      },
    );

    final result = await service.check();

    expect(result.status, UpdateStatus.available);
    expect(result.currentVersion, '1.0.0-beta1');
    expect(result.latestVersion, '1.1.0');
    expect(result.hasUpdate, isTrue);
    expect(
      result.releaseNotes,
      '**Important** [details](https://example.test/details)',
    );
    expect(result.downloadUrl, contains('/releases/tag/v1.1.0'));
    expect(result.artifactUrl, contains('/downloads/showrunner.zip'));
    expect(
      result.artifactSha256,
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    );
    expect(result.releaseDate, '2026-09-01T10:00:00Z');
    expect(result.canCheckForUpdates, isTrue);
    expect(result.checkedAt, isNotNull);
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
    expect(result.checkedAt, isNotNull);
  });

  test('reports when update checks are unavailable', () async {
    final service = UpdateCheckService(
      currentVersion: '1.0.0',
      canCheckForUpdates: false,
      fetcher: () async => throw StateError('must not fetch'),
    );

    final result = await service.check();

    expect(result.status, UpdateStatus.idle);
    expect(result.canCheckForUpdates, isFalse);
    expect(result.message, contains('unavailable'));
    expect(result.checkedAt, isNotNull);
  });

  test('coalesces concurrent checks and caches the completed result', () async {
    final release = Completer<JsonMap>();
    var fetchCount = 0;
    final service = UpdateCheckService(
      currentVersion: '1.0.0',
      fetcher: () {
        fetchCount++;
        return release.future;
      },
    );

    final first = service.check(force: true);
    final second = service.check(force: true);
    expect(fetchCount, 1);
    release.complete({'tag_name': 'v1.1.0'});
    final results = await Future.wait([first, second]);

    expect(identical(results[0], results[1]), isTrue);
    expect(identical(await service.check(), results[0]), isTrue);
    expect(fetchCount, 1);
  });

  test('uses the injected clock for stable check timestamps', () async {
    final service = UpdateCheckService(
      currentVersion: '1.0.0',
      clock: () => DateTime.utc(2026, 9, 23, 3, 17),
      fetcher: () async => {'tag_name': 'v1.0.0'},
    );

    final result = await service.check();

    expect(result.checkedAt, '2026-09-23T03:17:00.000Z');
  });

  test('forced update check refreshes a cached result', () async {
    var fetchCount = 0;
    final service = UpdateCheckService(
      currentVersion: '1.0.0',
      fetcher: () async => {'tag_name': 'v1.${++fetchCount}.0'},
    );

    final first = await service.check();
    final cached = await service.check();
    final refreshed = await service.check(force: true);

    expect(identical(first, cached), isTrue);
    expect(refreshed.latestVersion, '1.2.0');
    expect(fetchCount, 2);
  });
}
