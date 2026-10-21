import 'dart:io';
import 'safe_path.dart';

/// A directory remains anchored to the application root, including nested links.
final class PersistenceDirectory {
  PersistenceDirectory(this.root, Iterable<String> segments)
    : segments = List.unmodifiable(segments) {
    for (final segment in this.segments) {
      validateFileIdentifier(segment);
    }
  }
  final Directory root;
  final List<String> segments;
  Directory get directory =>
      segments.isEmpty ? root : safeRelativeDirectory(root, segments.join('/'));
  Future<File> file(List<String> names) =>
      containedFile(root, [...segments, ...names]);
  Future<Directory> resolve() async {
    final result = (await file(['.scope'])).parent;
    final type = await FileSystemEntity.type(result.path);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      throw FileSystemException('Expected a storage directory.', result.path);
    }
    return result;
  }
}
