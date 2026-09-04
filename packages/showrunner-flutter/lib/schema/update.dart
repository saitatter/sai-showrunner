import 'automation.dart';

enum UpdateStatus { idle, checking, available, upToDate, error }

class UpdateInfo {
  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.hasUpdate,
    this.releaseNotes = '',
    this.downloadUrl = '',
    this.releaseDate = '',
    this.status = UpdateStatus.idle,
    this.errorMessage,
  });

  final String currentVersion;
  final String latestVersion;
  final bool hasUpdate;
  final String releaseNotes;
  final String downloadUrl;
  final String releaseDate;
  final UpdateStatus status;
  final String? errorMessage;

  factory UpdateInfo.fromJson(JsonMap json, {required String currentVersion}) {
    final normalizedCurrent = normalizeVersion(currentVersion);
    final latest = normalizeVersion(
      (json['version'] ?? json['tag_name'])?.toString() ?? normalizedCurrent,
    );
    final hasUp = compareVersions(latest, normalizedCurrent) > 0;
    return UpdateInfo(
      currentVersion: normalizedCurrent,
      latestVersion: latest,
      hasUpdate: hasUp,
      releaseNotes: sanitizeReleaseNotes(
        (json['releaseNotes'] ?? json['body'])?.toString() ?? '',
      ),
      downloadUrl: (json['downloadUrl'] ?? json['html_url'])?.toString() ?? '',
      releaseDate:
          (json['releaseDate'] ?? json['published_at'])?.toString() ?? '',
      status: hasUp ? UpdateStatus.available : UpdateStatus.upToDate,
    );
  }

  JsonMap toJson() => <String, dynamic>{
    'currentVersion': currentVersion,
    'latestVersion': latestVersion,
    'hasUpdate': hasUpdate,
    'releaseNotes': releaseNotes,
    'downloadUrl': downloadUrl,
    'releaseDate': releaseDate,
  };
}

String normalizeVersion(String value) =>
    value.trim().replaceFirst(RegExp(r'^v', caseSensitive: false), '');

int compareVersions(String left, String right) {
  final leftParts = _versionParts(normalizeVersion(left));
  final rightParts = _versionParts(normalizeVersion(right));
  for (var index = 0; index < 3; index++) {
    final comparison = leftParts.numbers[index].compareTo(
      rightParts.numbers[index],
    );
    if (comparison != 0) return comparison;
  }
  if (leftParts.prerelease == rightParts.prerelease) return 0;
  if (leftParts.prerelease.isEmpty) return 1;
  if (rightParts.prerelease.isEmpty) return -1;
  return leftParts.prerelease.compareTo(rightParts.prerelease);
}

String sanitizeReleaseNotes(String value) {
  var sanitized = value.replaceAll(RegExp(r'<[^>]*>'), '');
  sanitized = sanitized.replaceAllMapped(
    RegExp(r'!\[([^\]]*)\]\([^)]*\)'),
    (match) => match.group(1) ?? '',
  );
  sanitized = sanitized.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\([^)]*\)'),
    (match) => match.group(1) ?? '',
  );
  sanitized = sanitized.replaceAll(RegExp(r'[`*_~]'), '');
  return sanitized.trim();
}

({List<int> numbers, String prerelease}) _versionParts(String value) {
  final withoutBuild = value.split('+').first;
  final pieces = withoutBuild.split('-');
  final numeric = pieces.first.split('.');
  return (
    numbers: [
      for (var index = 0; index < 3; index++)
        int.tryParse(index < numeric.length ? numeric[index] : '') ?? 0,
    ],
    prerelease: pieces.length > 1 ? pieces.sublist(1).join('-') : '',
  );
}
