import 'dart:io';

import '../media/domain/media_file.dart';
import '../media/scanner/media_file_enumerator.dart';
import '../media/scanner/media_library_service.dart';

export '../media/domain/media_file.dart'
    show
        MediaFileEntry,
        MediaKind,
        MediaMetadata,
        MediaScanMode,
        MediaScanResult,
        MediaScanStats;

final class MediaCatalogService {
  MediaCatalogService(this.userDirectory, {MediaMetadataReader? metadataReader})
    : _library = MediaLibraryService(
        userDirectory,
        metadataReader: metadataReader,
      );

  final Directory userDirectory;
  final MediaLibraryService _library;

  Directory get mediaDirectory => Directory('${userDirectory.path}/media');

  Future<List<MediaFileEntry>> discover() async => (await scan()).entries;

  Future<MediaScanResult> scan({MediaScanMode mode = MediaScanMode.quick}) =>
      _library.scan(mode: mode);

  Future<void> openMediaFolder() async {
    await mediaDirectory.create(recursive: true);
    if (Platform.isWindows) {
      await Process.start('explorer.exe', [mediaDirectory.path]);
    } else if (Platform.isMacOS) {
      await Process.start('open', [mediaDirectory.path]);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', [mediaDirectory.path]);
    }
  }

  Future<void> showInExplorer(MediaFileEntry entry) async {
    if (Platform.isWindows) {
      await Process.start('explorer.exe', ['/select,${entry.file.path}']);
    } else if (Platform.isMacOS) {
      await Process.start('open', ['-R', entry.file.path]);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', [entry.file.parent.path]);
    }
  }

  /// Copies supported files dropped from the desktop into the default media
  /// folder. Existing files are left untouched, matching the reference
  /// media store's duplicate handling.
  Future<int> importFiles(Iterable<File> sources) async {
    await mediaDirectory.create(recursive: true);
    var imported = 0;
    for (final source in sources) {
      if (!await source.exists()) continue;
      if (mediaKindForExtension(_extension(source.path)) == null) continue;
      final name = source.uri.pathSegments.last;
      if (name.isEmpty) continue;
      final destination = File('${mediaDirectory.path}/$name');
      if (_sameFile(source, destination) || await destination.exists()) {
        continue;
      }
      await source.copy(destination.path);
      imported++;
    }
    return imported;
  }
}

bool _sameFile(File left, File right) =>
    mediaPathKey(left.absolute.path) == mediaPathKey(right.absolute.path);

String _extension(String path) {
  final name = path.split(Platform.pathSeparator).last;
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}
