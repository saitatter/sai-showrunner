import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/media/scanner/media_library_watcher.dart';

void main() {
  test(
    'debounces filesystem events and stops delivering after dispose',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'showrunner-media-watcher-',
      );
      addTearDown(() => root.delete(recursive: true));
      var scans = 0;
      final scanCompleted = Completer<void>();
      final watcher = MediaLibraryWatcher(
        Directory('${root.path}/media'),
        debounce: const Duration(milliseconds: 40),
        onChanged: () async {
          scans++;
          if (!scanCompleted.isCompleted) scanCompleted.complete();
        },
      );

      await watcher.start();
      expect(watcher.isStarted, isTrue);
      await File('${root.path}/media/one.mp3').writeAsString('one');
      await File('${root.path}/media/two.mp3').writeAsString('two');
      await scanCompleted.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(scans, 1);

      await watcher.dispose();
      expect(watcher.isStarted, isFalse);
      await File('${root.path}/media/three.mp3').writeAsString('three');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(scans, 1);
    },
  );
}
