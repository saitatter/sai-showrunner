import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../schema/automation.dart';
import '../schema/update.dart';

typedef UpdateReleaseFetcher = Future<JsonMap> Function();

/// The packaged build supplies the semantic-release version at compile time.
/// Keep a useful development fallback so local `flutter run` builds still
/// present a stable version to the updater UI.
const showRunnerFlutterVersion = String.fromEnvironment(
  'SHOWRUNNER_VERSION',
  defaultValue: '2.0.0',
);

final class UpdateCheckService {
  UpdateCheckService({
    required this.currentVersion,
    this.repository = 'saitatter/sai-showrunner',
    this.timeout = const Duration(seconds: 8),
    this.fetcher,
    this.canCheckForUpdates = true,
  });

  final String currentVersion;
  final String repository;
  final Duration timeout;
  final UpdateReleaseFetcher? fetcher;
  final bool canCheckForUpdates;
  UpdateInfo? _lastResult;
  Future<UpdateInfo>? _inFlight;

  UpdateInfo? get lastResult => _lastResult;
  bool get isChecking => _inFlight != null;

  void remember(UpdateInfo result) {
    _lastResult = result;
  }

  Future<UpdateInfo> check({bool force = false}) {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final cached = _lastResult;
    if (!force && cached != null) return Future.value(cached);

    late final Future<UpdateInfo> request;
    request = _check()
        .then((result) {
          _lastResult = result;
          return result;
        })
        .whenComplete(() {
          if (identical(_inFlight, request)) _inFlight = null;
        });
    _inFlight = request;
    return request;
  }

  Future<UpdateInfo> _check() async {
    if (!canCheckForUpdates) {
      return UpdateInfo(
        currentVersion: normalizeVersion(currentVersion),
        latestVersion: normalizeVersion(currentVersion),
        hasUpdate: false,
        status: UpdateStatus.idle,
        canCheckForUpdates: false,
        checkedAt: _now(),
        message: 'Update checks are unavailable in this development build.',
      );
    }
    try {
      final release = await (fetcher?.call() ?? _fetchLatestRelease()).timeout(
        timeout,
      );
      final result = UpdateInfo.fromJson(
        release,
        currentVersion: currentVersion,
      );
      return _withCheckedAt(result, _now());
    } on Object catch (error) {
      return UpdateInfo(
        currentVersion: normalizeVersion(currentVersion),
        latestVersion: normalizeVersion(currentVersion),
        hasUpdate: false,
        status: UpdateStatus.error,
        errorMessage: _errorMessage(error),
        canCheckForUpdates: canCheckForUpdates,
        checkedAt: _now(),
      );
    }
  }

  Future<JsonMap> _fetchLatestRelease() async {
    final client = HttpClient()..userAgent = 'SAI-ShowRunner/$currentVersion';
    try {
      final request = await client.getUrl(
        Uri.parse('https://api.github.com/repos/$repository/releases/latest'),
      );
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'GitHub returned HTTP ${response.statusCode}.',
          uri: request.uri,
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const FormatException('The release response was not an object.');
      }
      return Map<String, dynamic>.from(decoded);
    } finally {
      client.close(force: true);
    }
  }
}

String _now() => DateTime.now().toUtc().toIso8601String();

UpdateInfo _withCheckedAt(UpdateInfo update, String checkedAt) => UpdateInfo(
  currentVersion: update.currentVersion,
  latestVersion: update.latestVersion,
  hasUpdate: update.hasUpdate,
  releaseNotes: update.releaseNotes,
  downloadUrl: update.downloadUrl,
  artifactUrl: update.artifactUrl,
  artifactSha256: update.artifactSha256,
  releaseDate: update.releaseDate,
  status: update.status,
  errorMessage: update.errorMessage,
  canCheckForUpdates: update.canCheckForUpdates,
  checkedAt: checkedAt,
  message: update.message,
  downloaded: update.downloaded,
);

String _errorMessage(Object error) {
  if (error is TimeoutException) return 'Update check timed out.';
  if (error is SocketException) return 'Update check is offline.';
  if (error is HttpException) return error.message;
  if (error is FormatException) return 'The update response was invalid.';
  return 'Unable to check for updates.';
}
