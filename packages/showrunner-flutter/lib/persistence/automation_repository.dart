import 'filesystem/persistence_directory.dart';
import 'document_revision.dart';
import 'filesystem/typed_document_file.dart';
import '../graph/domain/automation_document.dart';
import 'dart:io';

final class AutomationCatalogEntry {
  const AutomationCatalogEntry({
    required this.fileName,
    this.automation,
    this.error,
  });

  final String fileName;
  final AutomationDocument? automation;
  final Object? error;

  bool get isValid => automation != null && error == null;
}

abstract interface class AutomationStore {
  Future<AutomationDocument?> load();
  Future<void> save(
    AutomationDocument document, {
    DocumentRevision? expectedRevision,
    bool requireAbsent = false,
  });
  Future<void> delete({DocumentRevision? expectedRevision});
}

final class AutomationRepository implements AutomationStore {
  const AutomationRepository(this.file, {this.location});

  final File file;
  final PersistenceDirectory? location;

  TypedDocumentFile<AutomationDocument> get _store => TypedDocumentFile(
    file: file,
    location: location,
    kind: 'automation',
    decode: AutomationDocument.fromJson,
    encode: (document) => document.toJson(),
  );
  @override
  Future<AutomationDocument?> load() => _store.load();

  static Future<List<AutomationCatalogEntry>> loadDirectory(
    Directory directory, {
    PersistenceDirectory? location,
  }) async {
    await location?.resolve();
    if (!await directory.exists()) return const <AutomationCatalogEntry>[];
    final entries = <AutomationCatalogEntry>[];
    await for (final entity in directory.list()) {
      if (entity is! File || !entity.path.endsWith('.yaml')) continue;
      final fileName = entity.uri.pathSegments.last;
      try {
        entries.add(
          AutomationCatalogEntry(
            fileName: fileName,
            automation: await AutomationRepository(
              entity,
              location: location,
            ).load(),
          ),
        );
      } catch (error) {
        entries.add(AutomationCatalogEntry(fileName: fileName, error: error));
      }
    }
    entries.sort((left, right) => left.fileName.compareTo(right.fileName));
    return entries;
  }

  @override
  Future<void> save(
    AutomationDocument document, {
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
