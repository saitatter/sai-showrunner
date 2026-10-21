import 'filesystem/persistence_directory.dart';
import 'document_revision.dart';
import 'filesystem/typed_document_file.dart';
import 'dart:io';

import '../schema/profile.dart';

final class ProfileCatalogEntry {
  const ProfileCatalogEntry({required this.fileName, this.profile, this.error});

  final String fileName;
  final ShowRunnerProfile? profile;
  final Object? error;

  bool get isValid => profile != null && error == null;
}

abstract interface class ProfileStore {
  Future<ShowRunnerProfile?> load();
  Future<void> save(
    ShowRunnerProfile document, {
    DocumentRevision? expectedRevision,
    bool requireAbsent = false,
  });
  Future<void> delete({DocumentRevision? expectedRevision});
}

final class ProfileRepository implements ProfileStore {
  const ProfileRepository(this.file, {this.location});

  final File file;
  final PersistenceDirectory? location;

  static Future<List<ProfileCatalogEntry>> loadDirectory(
    Directory directory, {
    PersistenceDirectory? location,
  }) async {
    await location?.resolve();
    if (!await directory.exists()) return const <ProfileCatalogEntry>[];
    final entries = <ProfileCatalogEntry>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.yaml')) continue;
      final fileName = entity.uri.pathSegments.last;
      try {
        entries.add(
          ProfileCatalogEntry(
            fileName: fileName,
            profile: await ProfileRepository(entity, location: location).load(),
          ),
        );
      } catch (error) {
        entries.add(ProfileCatalogEntry(fileName: fileName, error: error));
      }
    }
    entries.sort((left, right) {
      final leftName = left.profile?.name ?? left.fileName;
      final rightName = right.profile?.name ?? right.fileName;
      return leftName.toLowerCase().compareTo(rightName.toLowerCase());
    });
    return entries;
  }

  TypedDocumentFile<ShowRunnerProfile> get _store => TypedDocumentFile(
    file: file,
    location: location,
    kind: 'profile',
    decode: ShowRunnerProfile.fromJson,
    encode: (document) => document.toJson(),
  );
  @override
  Future<ShowRunnerProfile?> load() => _store.load();
  @override
  Future<void> save(
    ShowRunnerProfile document, {
    DocumentRevision? expectedRevision,
    bool requireAbsent = false,
  }) => _store.save(
    document,
    expectedRevision: expectedRevision,
    requireAbsent: requireAbsent,
  );
  @override
  Future<void> delete({DocumentRevision? expectedRevision}) =>
      _store.delete(expectedRevision: expectedRevision);
}
