import '../schema/resource.dart';

final class ResourceDocumentManager {
  final Map<String, ResourceData> resources = {};
  final Map<String, bool> dirty = {};
  void open(ResourceData resource) {
    resources.putIfAbsent(resource.id, () => resource);
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

  void close(String id) {
    resources.remove(id);
    dirty.remove(id);
  }

  void retainOnly(String? id) {
    resources.removeWhere((key, _) => key != id);
    dirty.removeWhere((key, _) => key != id);
  }

  bool get hasUnsavedChanges => dirty.values.any((value) => value);
}
