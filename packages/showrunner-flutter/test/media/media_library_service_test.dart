import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/media/domain/media_file.dart';
import 'package:showrunner_flutter/media/scanner/media_library_service.dart';

void main() {
  test('quick scan skips metadata for unchanged files', () async {
    final root = await Directory.systemTemp.createTemp('showrunner-media-');
    addTearDown(() => root.delete(recursive: true));
    await Directory('${root.path}/media').create();
    final file = File('${root.path}/media/alerts.mp3');
    await file.writeAsString('initial', flush: true);
    final reader = _CountingMetadataReader();
    final service = MediaLibraryService(root, metadataReader: reader);

    final first = await service.scan();
    final second = await service.scan();

    expect(first.stats.added, 1);
    expect(first.stats.metadataReads, 1);
    expect(second.stats.unchanged, 1);
    expect(second.stats.metadataReads, 0);
    expect(second.entries.single.indexId, first.entries.single.indexId);
    expect(reader.calls, 1);
  });

  test('quick scan re-reads changed files and reconciles deletion', () async {
    final root = await Directory.systemTemp.createTemp('showrunner-media-');
    addTearDown(() => root.delete(recursive: true));
    await Directory('${root.path}/media').create();
    final file = File('${root.path}/media/alerts.mp3');
    await file.writeAsString('initial', flush: true);
    final reader = _CountingMetadataReader();
    final service = MediaLibraryService(root, metadataReader: reader);

    await service.scan();
    await file.writeAsString('changed content', flush: true);
    final changed = await service.scan();
    await file.delete();
    final removed = await service.scan();

    expect(changed.stats.changed, 1);
    expect(changed.stats.metadataReads, 1);
    expect(removed.entries, isEmpty);
    expect(removed.stats.removed, 1);
    expect(reader.calls, 2);
  });

  test('rename preserves the indexed media identity', () async {
    final root = await Directory.systemTemp.createTemp('showrunner-media-');
    addTearDown(() => root.delete(recursive: true));
    await Directory('${root.path}/media').create();
    final original = File('${root.path}/media/old-name.mp3');
    await original.writeAsString('same content', flush: true);
    final service = MediaLibraryService(
      root,
      metadataReader: _CountingMetadataReader(),
    );

    final before = await service.scan();
    final renamed = await original.rename('${root.path}/media/new-name.mp3');
    final after = await service.scan();

    expect(renamed.path, endsWith('new-name.mp3'));
    expect(after.stats.moved, 1);
    expect(after.stats.metadataReads, 0);
    expect(after.entries.single.indexId, before.entries.single.indexId);
    expect(after.entries.single.relativePath, 'new-name.mp3');
  });

  test(
    'full scan reads metadata even when fingerprints are unchanged',
    () async {
      final root = await Directory.systemTemp.createTemp('showrunner-media-');
      addTearDown(() => root.delete(recursive: true));
      await Directory('${root.path}/media').create();
      await File('${root.path}/media/alert.mp3').writeAsString('audio');
      final reader = _CountingMetadataReader();
      final service = MediaLibraryService(root, metadataReader: reader);

      await service.scan();
      final result = await service.scan(mode: MediaScanMode.full);

      expect(result.stats.mode, MediaScanMode.full);
      expect(result.stats.metadataReads, 1);
      expect(reader.calls, 2);
    },
  );
}

final class _CountingMetadataReader implements MediaMetadataReader {
  var calls = 0;

  @override
  Future<MediaMetadata?> read(MediaFileSnapshot file) async {
    calls++;
    return MediaMetadata(title: file.relativePath);
  }
}
