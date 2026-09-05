import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/services/media_catalog_service.dart';

void main() {
  test('discovers supported media recursively in stable order', () async {
    final root = await Directory.systemTemp.createTemp('showrunner-media-');
    addTearDown(() => root.delete(recursive: true));
    await File('${root.path}/media/nested/intro.PNG').create(recursive: true);
    await File('${root.path}/media/alert.mp3').create(recursive: true);
    await File('${root.path}/media/clip.webm').create(recursive: true);
    await File('${root.path}/media/notes.txt').create(recursive: true);

    final entries = await MediaCatalogService(root).discover();

    expect(entries.map((entry) => entry.relativePath), [
      'alert.mp3',
      'clip.webm',
      'nested/intro.PNG',
    ]);
    expect(entries[0].kind, MediaKind.audio);
    expect(entries[1].kind, MediaKind.video);
    expect(entries[2].kind, MediaKind.image);
    expect(entries[2].extension, 'png');
  });

  test('returns an empty catalog when the media directory is absent', () async {
    final root = await Directory.systemTemp.createTemp('showrunner-media-');
    addTearDown(() => root.delete(recursive: true));

    expect(await MediaCatalogService(root).discover(), isEmpty);
  });
}
