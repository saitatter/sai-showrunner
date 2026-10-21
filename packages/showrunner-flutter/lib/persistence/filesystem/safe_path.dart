import 'dart:io';

import 'package:path/path.dart' as p;

void validateFileIdentifier(String value) {
  if (value.isEmpty ||
      value == '.' ||
      value == '..' ||
      value.endsWith('.') ||
      value.endsWith(' ') ||
      RegExp(r'[\\/:\x00-\x1f<>"|?*]').hasMatch(value) ||
      RegExp(
        r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
        caseSensitive: false,
      ).hasMatch(value)) {
    throw ArgumentError.value(value, 'identifier', 'Unsafe file identifier.');
  }
}

Directory safeRelativeDirectory(Directory root, String relative) {
  for (final segment in relative.split('/')) {
    validateFileIdentifier(segment);
  }
  return Directory(p.joinAll([root.path, ...relative.split('/')]));
}

bool pathIsWithin(String root, String candidate) {
  final context = p.Context(
    style: Platform.isWindows ? p.Style.windows : p.Style.posix,
  );
  String normalize(String value) {
    final normalized = context.normalize(context.absolute(value));
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  return context.isWithin(normalize(root), normalize(candidate));
}

/// Resolves existing ancestors too, so junctions cannot redirect a new file.
Future<String> canonicalPath(String path) async {
  final absolute = p.normalize(p.absolute(path));
  if (await FileSystemEntity.type(absolute, followLinks: false) !=
      FileSystemEntityType.notFound) {
    return File(absolute).resolveSymbolicLinks();
  }
  final parent = p.dirname(absolute);
  if (parent == absolute) return absolute;
  return p.join(await canonicalPath(parent), p.basename(absolute));
}

Future<File> containedFile(Directory root, List<String> segments) async {
  for (final segment in segments) {
    validateFileIdentifier(segment);
  }
  if (segments.isEmpty) throw ArgumentError('A file path is required.');
  final file = File(p.joinAll([root.path, ...segments]));
  if (!pathIsWithin(
    await canonicalPath(root.path),
    await canonicalPath(file.path),
  )) {
    throw ArgumentError('File path leaves the allowed directory.');
  }
  return file;
}
