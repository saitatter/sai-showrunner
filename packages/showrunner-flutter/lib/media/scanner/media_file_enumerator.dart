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
      final extension = mediaExtensionForPath(entity.path);
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

String mediaExtensionForPath(String path) {
  final name = path.replaceAll('\\', '/').split('/').last;
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

MediaKind? mediaKindForExtension(String extension) {
  final normalized = extension.toLowerCase().replaceFirst('.', '');
  if (mediaImageExtensions.contains(normalized)) return MediaKind.image;
  if (mediaAudioExtensions.contains(normalized)) return MediaKind.audio;
  if (mediaVideoExtensions.contains(normalized)) return MediaKind.video;
  return null;
}

bool mediaExtensionSupportsKind(String extension, MediaKind kind) {
  final normalized = extension.toLowerCase().replaceFirst('.', '');
  if (normalized == 'ogg') {
    // OGG is present in both reference format lists; the container's actual
    // stream determines whether a file is audio or video.
    return kind == MediaKind.audio || kind == MediaKind.video;
  }
  return mediaKindForExtension(normalized) == kind;
}

/// Formats supported by the reference media contract.
///
/// Keep these sets public so the media browser, picker and import path cannot
/// silently drift apart again.
const mediaImageExtensions = {
  'gif',
  'png',
  'jpg',
  'jpeg',
  'apng',
  'avif',
  'webp',
  'svg',
  'bmp',
  'tiff',
};
const mediaAudioExtensions = {'mp3', 'wav', 'ogg', 'flac', 'm4a'};
const mediaVideoExtensions = {'mp4', 'webm', 'ogg', 'mov', 'mkv', 'avi'};
