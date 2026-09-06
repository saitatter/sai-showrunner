import 'dart:io';

import '../domain/media_file.dart';
import '../persistence/media_index_store.dart';
import 'media_file_enumerator.dart';
import 'media_library_watcher.dart';

abstract interface class MediaMetadataReader {
  Future<MediaMetadata?> read(MediaFileSnapshot file);
}

final class EmptyMediaMetadataReader implements MediaMetadataReader {
  const EmptyMediaMetadataReader();

  @override
  Future<MediaMetadata?> read(MediaFileSnapshot file) async => null;
}

final class MediaLibraryService {
  MediaLibraryService(
    this.userDirectory, {
    MediaIndexStore? indexStore,
    MediaMetadataReader? metadataReader,
  }) : indexStore =
           indexStore ??
           MediaIndexStore(
             File('${userDirectory.path}/state/media-library.sqlite'),
           ),
       metadataReader = metadataReader ?? const EmptyMediaMetadataReader();

  final Directory userDirectory;
  final MediaIndexStore indexStore;
  final MediaMetadataReader metadataReader;

  Directory get mediaDirectory => Directory('${userDirectory.path}/media');

  Future<MediaScanResult> scan({
    MediaScanMode mode = MediaScanMode.quick,
  }) async {
    final enumerator = MediaFileEnumerator(mediaDirectory);
    final snapshots = await enumerator.enumerate();
    final root = mediaDirectory.absolute.path;
    final generation = await indexStore.nextGeneration(root);
    final existing = await indexStore.loadRoot(root);
    final byPath = {for (final record in existing) record.pathKey: record};
    final seenIds = <int>{};
    final unmatched = existing
        .where(
          (record) =>
              !snapshots.any((snapshot) => snapshot.pathKey == record.pathKey),
        )
        .toList(growable: false);
    final availableMoves = [...unmatched];
    final records = <MediaIndexRecord>[];
    var unchanged = 0;
    var metadataReads = 0;
    var added = 0;
    var changed = 0;
    var moved = 0;

    for (final snapshot in snapshots) {
      var previous = byPath[snapshot.pathKey];
      var wasMoved = false;
      if (previous == null) {
        final moveIndex = _findMoveCandidate(availableMoves, snapshot);
        if (moveIndex != -1) {
          previous = availableMoves.removeAt(moveIndex);
          wasMoved = true;
          moved++;
        }
      }

      final fingerprintMatches =
          previous != null && snapshot.hasSameFingerprint(previous);
      final shouldReadMetadata =
          mode == MediaScanMode.full || !fingerprintMatches;
      MediaMetadata? metadata = previous?.metadata;
      var lastMetadataScanMs = previous?.lastMetadataScanMs;
      var scanError = previous?.scanError;
      if (shouldReadMetadata) {
        metadataReads++;
        try {
          metadata = await metadataReader.read(snapshot);
          lastMetadataScanMs = DateTime.now().millisecondsSinceEpoch;
          scanError = null;
        } on Object catch (error) {
          scanError = '$error';
        }
      }

      if (previous == null) {
        added++;
      } else if (!fingerprintMatches && !wasMoved) {
        changed++;
      } else if (fingerprintMatches && !wasMoved) {
        unchanged++;
      }
      if (previous?.id case final id?) seenIds.add(id);
      records.add(
        MediaIndexRecord(
          id: previous?.id,
          root: root,
          relativePath: snapshot.relativePath,
          pathKey: snapshot.pathKey,
          extension: snapshot.extension,
          kind: snapshot.kind,
          sizeBytes: snapshot.sizeBytes,
          modifiedAtMs: snapshot.modifiedAtMs,
          metadata: metadata,
          extractorVersion: previous?.extractorVersion ?? '',
          metadataSchemaVersion: previous?.metadataSchemaVersion ?? 1,
          lastMetadataScanMs: lastMetadataScanMs,
          scanError: scanError,
        ),
      );
    }

    final removed = [
      ...existing.where(
        (record) => record.id != null && !seenIds.contains(record.id),
      ),
    ];
    final persistedRecords = await indexStore.reconcile(
      root: root,
      generation: generation,
      records: records,
      removedIds: removed.map((record) => record.id!).toList(growable: false),
    );
    return MediaScanResult(
      entries: persistedRecords
          .map((record) => record.toEntry())
          .toList(growable: false),
      stats: MediaScanStats(
        mode: mode,
        enumerated: snapshots.length,
        unchanged: unchanged,
        metadataReads: metadataReads,
        added: added,
        changed: changed,
        moved: moved,
        removed: removed.length,
        errors: persistedRecords
            .where((record) => record.scanError != null)
            .length,
      ),
    );
  }

  MediaLibraryWatcher watch({
    required Future<void> Function() onChanged,
    Duration debounce = const Duration(milliseconds: 250),
    void Function(Object error, StackTrace stackTrace)? onError,
  }) => MediaLibraryWatcher(
    mediaDirectory,
    onChanged: onChanged,
    debounce: debounce,
    onError: onError,
  );
}

int _findMoveCandidate(
  List<MediaIndexRecord> candidates,
  MediaFileSnapshot snapshot,
) {
  final matches = <int>[];
  for (var index = 0; index < candidates.length; index++) {
    final candidate = candidates[index];
    if (snapshot.hasSameFingerprint(candidate)) matches.add(index);
  }
  return matches.length == 1 ? matches.single : -1;
}
