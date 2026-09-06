import 'dart:io';

import '../domain/media_file.dart';

final class MediaFileEnumerator {
  MediaFileEnumerator(this.root);

  final Directory root;

  Future<List<MediaFileSnapshot>> enumerate() async {
    if (!await root.exists()) return const <MediaFileSnapshot>[];

    final snapshots = <MediaFileSnapshot>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final extension = _extension(entity.path);
      final kind = mediaKindForExtension(extension);
      if (kind == null) continue;
      try {
        final stat = await entity.stat();
        final relativePath = _relativePath(entity);
        snapshots.add(
          MediaFileSnapshot(
            file: entity,
            relativePath: relativePath,
            pathKey: mediaPathKey(entity.path),
            extension: extension,
            kind: kind,
            sizeBytes: stat.size,
            modifiedAt: stat.modified,
          ),
        );
      } on FileSystemException {
        // A file can disappear or become inaccessible during enumeration.
        // The next scan will reconcile it when it is visible again.
      }
    }
    snapshots.sort(
      (left, right) => left.relativePath.toLowerCase().compareTo(
        right.relativePath.toLowerCase(),
      ),
    );
    return snapshots;
  }

  String _relativePath(File file) {
    final rootPath = root.absolute.path.endsWith(Platform.pathSeparator)
        ? root.absolute.path
        : '${root.absolute.path}${Platform.pathSeparator}';
    final relative = file.absolute.path.startsWith(rootPath)
        ? file.absolute.path.substring(rootPath.length)
        : file.uri.pathSegments.last;
    return relative.replaceAll('\\', '/');
  }
}

String mediaPathKey(String path) => path.replaceAll('\\', '/').toLowerCase();

String _extension(String path) {
  final name = path.split(Platform.pathSeparator).last;
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

MediaKind? mediaKindForExtension(String extension) {
  if (_imageExtensions.contains(extension)) return MediaKind.image;
  if (_audioExtensions.contains(extension)) return MediaKind.audio;
  if (_videoExtensions.contains(extension)) return MediaKind.video;
  return null;
}

const _imageExtensions = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};
const _audioExtensions = {'mp3', 'wav', 'ogg', 'flac', 'm4a'};
const _videoExtensions = {'mp4', 'webm', 'mov', 'mkv', 'avi'};
