import 'dart:io';
import '../../persistence/filesystem/safe_path.dart';

/// Shares canonical path containment across HTTP resources and audio URLs.
final class OverlayMediaResources {
  const OverlayMediaResources({this.mediaRoot, this.ttsRoot});
  final Directory? mediaRoot, ttsRoot;

  Future<File?> fileFor(String kind, List<String> segments) async {
    final root = switch (kind) {
      'default' => mediaRoot,
      'tts-cache' => ttsRoot,
      _ => null,
    };
    if (root == null) return null;
    final file = await containedFile(root, segments);
    return await file.exists() ? file : null;
  }

  Future<String?> browserUrl(String source, String overlayId) async {
    final file = File(source);
    if (!await file.exists()) return null;
    final absolutePath = await file.resolveSymbolicLinks();
    final mediaRelative = await _relativeTo(mediaRoot, absolutePath);
    if (mediaRelative != null) {
      return '/overlays/${Uri.encodeComponent(overlayId)}/media/default/$mediaRelative';
    }
    final ttsRelative = await _relativeTo(ttsRoot, absolutePath);
    if (ttsRelative != null) {
      return '/overlays/${Uri.encodeComponent(overlayId)}/media/tts-cache/$ttsRelative';
    }
    return null;
  }

  Future<String?> _relativeTo(Directory? root, String filePath) async {
    if (root == null || !await root.exists()) return null;
    final rootPath = (await root.resolveSymbolicLinks()).replaceAll('\\', '/');
    final normalizedRoot =
        (Platform.isWindows ? rootPath.toLowerCase() : rootPath).replaceFirst(
          RegExp(r'/+$'),
          '',
        );
    final normalizedFilePath = filePath.replaceAll('\\', '/');
    final comparable = Platform.isWindows
        ? normalizedFilePath.toLowerCase()
        : normalizedFilePath;
    if (!comparable.startsWith('$normalizedRoot/')) {
      return null;
    }
    final relative = normalizedFilePath.substring(normalizedRoot.length + 1);
    if (relative.split(RegExp(r'[/\\]+')).any((part) => part == '..')) {
      return null;
    }
    return relative
        .split(RegExp(r'[/\\]+'))
        .where((part) => part.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
  }
}
