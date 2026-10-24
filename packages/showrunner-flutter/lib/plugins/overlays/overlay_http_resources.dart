import 'dart:convert';
import 'dart:io';
import '../../persistence/filesystem/safe_path.dart';
import '../../schema/resource.dart';
import 'manifest.dart';
import 'overlay_access.dart';
import 'overlay_media_resources.dart';
import 'overlay_browser_projection.dart';

/// Read-only HTTP resources for one overlay runtime; no peer or event ownership.
final class OverlayHttpResourceHandler {
  OverlayHttpResourceHandler({
    required this.overlayStore,
    required this.access,
    required this.registerAudioOutput,
    this.webRoot,
    required this.media,
  });
  final OverlayResourceStore overlayStore;
  final OverlayAccessTokens access;
  final void Function(String overlayId) registerAudioOutput;
  final Directory? webRoot;
  final OverlayMediaResources media;
  bool _disposed = false;
  Future<Map<String, dynamic>> projectConfig(ResourceData resource) =>
      projectOverlayConfig(resource, media);

  void close() {
    _disposed = true;
  }

  Future<bool> handle(HttpRequest request) async {
    if (_disposed) {
      await _respond(request, HttpStatus.serviceUnavailable);
      return true;
    }
    final segments = request.uri.pathSegments;
    if (segments.isEmpty) return false;
    if (segments.first != 'overlays') return false;
    request.response.headers.set('Cache-Control', 'no-store');
    request.response.headers.set('Referrer-Policy', 'no-referrer');

    if (segments.length >= 3 && segments[1] != 'assets') {
      final id = segments[1];
      if (segments[2] == 'session' &&
          segments.length == 3 &&
          request.method == 'POST') {
        if (!access.accepts(
          id,
          request.headers.value('x-showrunner-overlay'),
        )) {
          await _respond(request, HttpStatus.unauthorized);
          return true;
        }
        request.response.cookies.add(
          Cookie(OverlayAccessTokens.cookieName, access.forOverlay(id))
            ..path = '/overlays/${Uri.encodeComponent(id)}'
            ..httpOnly = true
            ..sameSite = SameSite.strict
            ..maxAge = 86400,
        );
        await _respond(request, HttpStatus.noContent);
        return true;
      }
      if ((segments[2] == 'config' || segments[2] == 'media') &&
          !access.authorizes(request, id)) {
        await _respond(request, HttpStatus.unauthorized);
        return true;
      }
      if (segments[2] == 'media' && request.method == 'GET') {
        final resource = await overlayStore.load(id);
        if (_disposed || resource == null) {
          await _respond(
            request,
            _disposed ? HttpStatus.serviceUnavailable : HttpStatus.notFound,
          );
          return true;
        }
        return _serveMedia(request, segments.skip(2).toList());
      }
    }
    if (request.method != 'GET') return false;

    if (segments.length == 3 && segments[2] == 'config') {
      final resource = await overlayStore.load(segments[1]);
      if (_disposed) {
        await _respond(request, HttpStatus.serviceUnavailable);
        return true;
      }
      if (resource == null) {
        await _respond(request, HttpStatus.notFound);
        return true;
      }
      registerAudioOutput(resource.id);
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json;
      request.response.write(jsonEncode(await projectConfig(resource)));
      await request.response.close();
      return true;
    }

    final root = webRoot;
    if (root == null) return false;
    File? file;
    if (segments.length == 2) {
      final resource = await overlayStore.load(segments[1]);
      if (_disposed) {
        await _respond(request, HttpStatus.serviceUnavailable);
        return true;
      }
      if (resource == null) {
        await _respond(request, HttpStatus.notFound);
        return true;
      }
      file = File('${root.path}/overlay.html');
    } else if (segments.length > 2 && segments[1] == 'assets') {
      if (segments
          .skip(2)
          .any((segment) => segment == '..' || segment == '.')) {
        await _respond(request, HttpStatus.badRequest);
        return true;
      }
      try {
        file = await containedFile(root, segments.skip(1).toList());
      } on ArgumentError {
        await _respond(request, HttpStatus.badRequest);
        return true;
      }
    }
    if (file == null) return false;
    if (!await file.exists()) {
      await _respond(request, HttpStatus.notFound);
      return true;
    }
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = _contentType(file.path);
    await file.openRead().pipe(request.response);
    return true;
  }

  Future<bool> _serveMedia(HttpRequest request, List<String> segments) async {
    if (segments.length < 3) return false;
    File? file;
    try {
      file = await media.fileFor(segments[1], segments.skip(2).toList());
    } on ArgumentError {
      await _respond(request, HttpStatus.badRequest);
      return true;
    }
    if (_disposed || file == null) {
      await _respond(
        request,
        _disposed ? HttpStatus.serviceUnavailable : HttpStatus.notFound,
      );
      return true;
    }
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = _contentType(file.path);
    await file.openRead().pipe(request.response);
    return true;
  }
}

Directory? discoverOverlayWebRoot() {
  final executableDirectory = File(Platform.resolvedExecutable).parent;
  final candidates = [
    Directory('${executableDirectory.path}/obs-overlay'),
    Directory('${Directory.current.path}/obs-overlay'),
    Directory(
      '${Directory.current.path}/../showrunner-obs-overlay/dist/obs-overlay',
    ),
  ];
  for (final candidate in candidates) {
    if (candidate.existsSync()) return candidate;
  }
  return null;
}

ContentType _contentType(String path) {
  return switch (path.toLowerCase().split('.').last) {
    'html' => ContentType.html,
    'css' => ContentType('text', 'css'),
    'js' => ContentType('application', 'javascript'),
    'json' => ContentType.json,
    'svg' => ContentType('image', 'svg+xml'),
    'png' => ContentType('image', 'png'),
    'jpg' || 'jpeg' => ContentType('image', 'jpeg'),
    'webp' => ContentType('image', 'webp'),
    'woff' => ContentType('font', 'woff'),
    'woff2' => ContentType('font', 'woff2'),
    _ => ContentType('application', 'octet-stream'),
  };
}

Future<void> _respond(HttpRequest request, int statusCode) async {
  request.response
    ..statusCode = statusCode
    ..headers.contentLength = 0;
  await request.response.close();
}
