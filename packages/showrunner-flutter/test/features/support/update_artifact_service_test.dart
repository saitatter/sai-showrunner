import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/schema/update.dart';
import 'package:showrunner_flutter/services/update_artifact_service.dart';

void main() {
  test(
    'downloads an artifact through a temporary file and renames it',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'showrunner-update-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final service = UpdateArtifactService(
        downloader: (uri, destination) async {
          expect(uri.toString(), 'https://example.test/release.zip');
          await destination.writeAsString('zip-bytes');
        },
      );

      final artifact = await service.download(
        const UpdateInfo(
          currentVersion: '1.0.0',
          latestVersion: '1.1.0/preview',
          hasUpdate: true,
          artifactUrl: 'https://example.test/release.zip',
        ),
        directory: directory,
      );

      expect(
        artifact.path,
        endsWith('ShowRunner-Flutter-windows-1.1.0_preview.zip'),
      );
      expect(await artifact.readAsString(), 'zip-bytes');
      expect(await File('${artifact.path}.part').exists(), isFalse);
    },
  );

  test('removes an incomplete artifact after download failure', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-update-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final service = UpdateArtifactService(
      downloader: (uri, destination) async {
        await destination.writeAsString('partial');
        throw const SocketException('offline');
      },
    );

    await expectLater(
      service.download(
        const UpdateInfo(
          currentVersion: '1.0.0',
          latestVersion: '1.1.0',
          hasUpdate: true,
          artifactUrl: 'https://example.test/release.zip',
        ),
        directory: directory,
      ),
      throwsA(isA<SocketException>()),
    );
    expect(
      await File(
        '${directory.path}/ShowRunner-Flutter-windows-1.1.0.zip.part',
      ).exists(),
      isFalse,
    );
  });

  test(
    'verifies an advertised SHA-256 digest before publishing the artifact',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'showrunner-update-verified-',
      );
      addTearDown(() => directory.delete(recursive: true));
      const bytes = 'zip-bytes';
      final digest = sha256.convert(bytes.codeUnits).toString();
      final service = UpdateArtifactService(
        downloader: (_, destination) async => destination.writeAsString(bytes),
      );

      final artifact = await service.download(
        UpdateInfo(
          currentVersion: '1.0.0',
          latestVersion: '1.1.0',
          hasUpdate: true,
          artifactUrl: 'https://example.test/release.zip',
          artifactSha256: digest,
        ),
        directory: directory,
      );

      expect(await artifact.readAsString(), bytes);
    },
  );

  test('rejects an artifact with a mismatched SHA-256 digest', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-update-mismatch-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final service = UpdateArtifactService(
      downloader: (_, destination) async =>
          destination.writeAsString('zip-bytes'),
    );

    await expectLater(
      service.download(
        const UpdateInfo(
          currentVersion: '1.0.0',
          latestVersion: '1.1.0',
          hasUpdate: true,
          artifactUrl: 'https://example.test/release.zip',
          artifactSha256:
              'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
        ),
        directory: directory,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      await File(
        '${directory.path}/ShowRunner-Flutter-windows-1.1.0.zip.part',
      ).exists(),
      isFalse,
    );
  });

  test('rejects non-http artifact URLs before creating files', () async {
    final directory = await Directory.systemTemp.createTemp(
      'showrunner-update-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final service = UpdateArtifactService(
      downloader: (_, _) async => fail('The downloader must not be called.'),
    );

    await expectLater(
      service.download(
        const UpdateInfo(
          currentVersion: '1.0.0',
          latestVersion: '1.1.0',
          hasUpdate: true,
          artifactUrl: 'file:///unsafe.zip',
        ),
        directory: directory,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(await directory.list().isEmpty, isTrue);
  });
}
