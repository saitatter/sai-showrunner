import 'dart:async';
import 'dart:io';

import '../schema/update.dart';

typedef UpdateArtifactDownloader =
    Future<void> Function(Uri uri, File destination);

/// Downloads a release artifact without exposing a partially written archive.
///
/// Installation is intentionally a separate concern: replacing a running
/// Windows bundle needs a packaged, independently tested helper process.
final class UpdateArtifactService {
  const UpdateArtifactService({this.downloader = _download});

  final UpdateArtifactDownloader downloader;

  Future<File> download(
    UpdateInfo update, {
    required Directory directory,
  }) async {
    final url = Uri.tryParse(update.artifactUrl.trim());
    if (url == null || !{'http', 'https'}.contains(url.scheme)) {
      throw const FormatException('The update artifact URL is invalid.');
    }
    await directory.create(recursive: true);
    final version = normalizeVersion(
      update.latestVersion,
    ).replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    final destination = File(
      '${directory.path}/ShowRunner-Flutter-windows-$version.zip',
    );
    final partial = File('${destination.path}.part');
    try {
      await downloader(url, partial);
      if (!await partial.exists() || await partial.length() == 0) {
        throw const FormatException('The downloaded update artifact is empty.');
      }
      if (await destination.exists()) await destination.delete();
      return await partial.rename(destination.path);
    } on Object {
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }
}

Future<void> _download(Uri uri, File destination) async {
  final client = HttpClient()..userAgent = 'SAI-ShowRunner-updater';
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/zip');
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Update artifact download failed with HTTP ${response.statusCode}.',
        uri: uri,
      );
    }
    final sink = destination.openWrite();
    try {
      await response.pipe(sink);
    } on Object {
      await sink.close();
      rethrow;
    }
  } finally {
    client.close(force: true);
  }
}
