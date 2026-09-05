import 'dart:io';

enum MediaKind { image, audio, video }

final class MediaFileEntry {
  const MediaFileEntry({
    required this.file,
    required this.relativePath,
    required this.extension,
    required this.kind,
  });

  final File file;
  final String relativePath;
  final String extension;
  final MediaKind kind;
}

final class MediaCatalogService {
  MediaCatalogService(this.userDirectory);

  final Directory userDirectory;

  Directory get mediaDirectory => Directory('${userDirectory.path}/media');

  Future<List<MediaFileEntry>> discover() async {
    if (!await mediaDirectory.exists()) return const <MediaFileEntry>[];

    final entries = <MediaFileEntry>[];
    await for (final entity in mediaDirectory.list(recursive: true)) {
      if (entity is! File) continue;
      final extension = _extension(entity.path);
      final kind = _kindFor(extension);
      if (kind == null) continue;
      entries.add(
        MediaFileEntry(
          file: entity,
          relativePath: _relativePath(entity),
          extension: extension,
          kind: kind,
        ),
      );
    }
    entries.sort(
      (left, right) => left.relativePath.toLowerCase().compareTo(
        right.relativePath.toLowerCase(),
      ),
    );
    return entries;
  }

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

  String _relativePath(File file) {
    final root = mediaDirectory.path.endsWith(Platform.pathSeparator)
        ? mediaDirectory.path
        : '${mediaDirectory.path}${Platform.pathSeparator}';
    final relative = file.path.startsWith(root)
        ? file.path.substring(root.length)
        : file.uri.pathSegments.last;
    return relative.replaceAll('\\', '/');
  }
}

String _extension(String path) {
  final name = path.split(Platform.pathSeparator).last;
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

MediaKind? _kindFor(String extension) {
  if (_imageExtensions.contains(extension)) return MediaKind.image;
  if (_audioExtensions.contains(extension)) return MediaKind.audio;
  if (_videoExtensions.contains(extension)) return MediaKind.video;
  return null;
}

const _imageExtensions = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};
const _audioExtensions = {'mp3', 'wav', 'ogg', 'flac', 'm4a'};
const _videoExtensions = {'mp4', 'webm', 'mov', 'mkv', 'avi'};
