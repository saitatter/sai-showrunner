import 'dart:io';

enum MediaKind { image, audio, video }

enum MediaScanMode { quick, full }

final class MediaMetadata {
  const MediaMetadata({
    this.title,
    this.artists = const <String>[],
    this.albumArtists = const <String>[],
    this.album,
    this.genres = const <String>[],
    this.year,
    this.track,
    this.disc,
    this.durationMs,
    this.bitrate,
    this.sampleRate,
    this.channels,
    this.musicBrainzRecordingId,
    this.replayGain,
    this.hasArtwork = false,
  });

  final String? title;
  final List<String> artists;
  final List<String> albumArtists;
  final String? album;
  final List<String> genres;
  final int? year;
  final int? track;
  final int? disc;
  final int? durationMs;
  final int? bitrate;
  final int? sampleRate;
  final int? channels;
  final String? musicBrainzRecordingId;
  final double? replayGain;
  final bool hasArtwork;

  Map<String, dynamic> toJson() => {
    if (title != null) 'title': title,
    if (artists.isNotEmpty) 'artists': artists,
    if (albumArtists.isNotEmpty) 'albumArtists': albumArtists,
    if (album != null) 'album': album,
    if (genres.isNotEmpty) 'genres': genres,
    if (year != null) 'year': year,
    if (track != null) 'track': track,
    if (disc != null) 'disc': disc,
    if (durationMs != null) 'durationMs': durationMs,
    if (bitrate != null) 'bitrate': bitrate,
    if (sampleRate != null) 'sampleRate': sampleRate,
    if (channels != null) 'channels': channels,
    if (musicBrainzRecordingId != null)
      'musicBrainzRecordingId': musicBrainzRecordingId,
    if (replayGain != null) 'replayGain': replayGain,
    'hasArtwork': hasArtwork,
  };

  factory MediaMetadata.fromJson(Map<String, dynamic> json) => MediaMetadata(
    title: json['title'] as String?,
    artists: _strings(json['artists']),
    albumArtists: _strings(json['albumArtists']),
    album: json['album'] as String?,
    genres: _strings(json['genres']),
    year: (json['year'] as num?)?.toInt(),
    track: (json['track'] as num?)?.toInt(),
    disc: (json['disc'] as num?)?.toInt(),
    durationMs: (json['durationMs'] as num?)?.toInt(),
    bitrate: (json['bitrate'] as num?)?.toInt(),
    sampleRate: (json['sampleRate'] as num?)?.toInt(),
    channels: (json['channels'] as num?)?.toInt(),
    musicBrainzRecordingId: json['musicBrainzRecordingId'] as String?,
    replayGain: (json['replayGain'] as num?)?.toDouble(),
    hasArtwork: json['hasArtwork'] == true,
  );
}

final class MediaFileSnapshot {
  const MediaFileSnapshot({
    required this.file,
    required this.relativePath,
    required this.pathKey,
    required this.extension,
    required this.kind,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  final File file;
  final String relativePath;
  final String pathKey;
  final String extension;
  final MediaKind kind;
  final int sizeBytes;
  final DateTime modifiedAt;

  int get modifiedAtMs => modifiedAt.millisecondsSinceEpoch;

  bool hasSameFingerprint(MediaIndexRecord record) =>
      sizeBytes == record.sizeBytes && modifiedAtMs == record.modifiedAtMs;
}

final class MediaIndexRecord {
  const MediaIndexRecord({
    this.id,
    required this.root,
    required this.relativePath,
    required this.pathKey,
    required this.extension,
    required this.kind,
    required this.sizeBytes,
    required this.modifiedAtMs,
    this.metadata,
    this.extractorVersion = '',
    this.metadataSchemaVersion = 1,
    this.lastMetadataScanMs,
    this.scanError,
  });

  final int? id;
  final String root;
  final String relativePath;
  final String pathKey;
  final String extension;
  final MediaKind kind;
  final int sizeBytes;
  final int modifiedAtMs;
  final MediaMetadata? metadata;
  final String extractorVersion;
  final int metadataSchemaVersion;
  final int? lastMetadataScanMs;
  final String? scanError;

  MediaFileEntry toEntry() => MediaFileEntry(
    file: File('$root${Platform.pathSeparator}$relativePath'),
    relativePath: relativePath,
    extension: extension,
    kind: kind,
    sizeBytes: sizeBytes,
    modifiedAt: DateTime.fromMillisecondsSinceEpoch(modifiedAtMs),
    metadata: metadata,
    indexId: id,
  );
}

final class MediaFileEntry {
  const MediaFileEntry({
    required this.file,
    required this.relativePath,
    required this.extension,
    required this.kind,
    this.sizeBytes = 0,
    this.modifiedAt,
    this.metadata,
    this.indexId,
  });

  final File file;
  final String relativePath;
  final String extension;
  final MediaKind kind;
  final int sizeBytes;
  final DateTime? modifiedAt;
  final MediaMetadata? metadata;
  final int? indexId;
}

final class MediaScanStats {
  const MediaScanStats({
    required this.mode,
    required this.enumerated,
    required this.unchanged,
    required this.metadataReads,
    required this.added,
    required this.changed,
    required this.moved,
    required this.removed,
    required this.errors,
  });

  final MediaScanMode mode;
  final int enumerated;
  final int unchanged;
  final int metadataReads;
  final int added;
  final int changed;
  final int moved;
  final int removed;
  final int errors;
}

final class MediaScanResult {
  const MediaScanResult({required this.entries, required this.stats});

  final List<MediaFileEntry> entries;
  final MediaScanStats stats;
}

List<String> _strings(Object? value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const <String>[];
