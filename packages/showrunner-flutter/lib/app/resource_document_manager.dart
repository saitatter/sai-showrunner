import '../persistence/document_revision.dart';
import '../schema/resource.dart';

final class ResourceDocumentManager {
  final Map<String, ResourceData> resources = {};
  final Map<String, bool> dirty = {};
  final Map<String, DocumentRevision> storageRevisions = {};
  void open(ResourceData resource) {
    if (resources.containsKey(resource.id)) return;
    resources[resource.id] = resource;
    storageRevisions[resource.id] = DocumentRevision.of(resource.toJson());
  }

  void update(ResourceData resource, {required bool isDirty}) {
    resources[resource.id] = resource;
    dirty[resource.id] = isDirty;
  }

  void markSaved(ResourceData resource) => update(resource, isDirty: false);

  /// A completed write must not replace edits made while it was in flight,
  /// or reopen a document that was closed in the meantime.
  void markSavedIfCurrent(ResourceData resource, ResourceData? expected) {
    if (resources.containsKey(resource.id) &&
        identical(resources[resource.id], expected)) {
      markSaved(resource);
    }
  }

  void acceptPersisted(ResourceData resource, DocumentRevision? previous) {
    if (resources.containsKey(resource.id) &&
        identical(storageRevisions[resource.id], previous)) {
      storageRevisions[resource.id] = DocumentRevision.of(resource.toJson());
    }
  }

  void close(String id) {
    resources.remove(id);
    dirty.remove(id);
    storageRevisions.remove(id);
  }

  void retainOnly(String? id) {
    resources.removeWhere((key, _) => key != id);
    dirty.removeWhere((key, _) => key != id);
    storageRevisions.removeWhere((key, _) => key != id);
  }

  bool get hasUnsavedChanges => dirty.values.any((value) => value);
}
