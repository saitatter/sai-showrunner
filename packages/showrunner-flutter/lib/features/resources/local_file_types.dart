/// File types accepted by resource editors that reference local assets.
///
/// This is intentionally a small picker contract. It does not index, catalog,
/// scan, or watch the filesystem; callers only use it while choosing a file.
enum MediaKind { image, audio, video }

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
    // OGG may contain either an audio or a video stream.
    return kind == MediaKind.audio || kind == MediaKind.video;
  }
  return mediaKindForExtension(normalized) == kind;
}

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
