import 'persistence_directory.dart';
import 'dart:convert';
import 'dart:io';
import 'package:yaml/yaml.dart';
import '../../schema/json.dart';
import '../document_codec.dart';
import '../document_revision.dart';
import 'atomic_file.dart';
import 'file_transaction.dart';
import 'safe_path.dart';

/// One authoritative file uses atomic replacement, never a multi-file journal.
/// Its OS owner lock serializes validation, revision comparison and publication.
final class TypedDocumentFile<T> {
  const TypedDocumentFile({
    required this.file,
    required this.kind,
    required this.decode,
    required this.encode,
    this.format,
    this.location,
  });
  final File file;
  final PersistenceDirectory? location;
  final String kind;
  final T Function(JsonMap) decode;
  final JsonMap Function(T) encode;
  final String Function(JsonMap)? format;
  String get _name => file.uri.pathSegments.last;
  FileTransaction get _owner => FileTransaction(
    directory: file.parent,
    id: _name,
    targets: const {},
    location: location,
  );
  Future<File> _checked() =>
      location?.file([_name]) ?? containedFile(file.parent, [_name]);

  Future<T?> _read() async {
    final source = await _checked();
    if (!await source.exists()) return null;
    final contents = await source.readAsString();
    try {
      Object? value;
      try {
        value = jsonDecode(contents);
      } on FormatException {
        value = decodeYamlValue(loadYaml(contents));
      }
      if (value is! Map) throw const FormatException();
      return decode(Map<String, dynamic>.from(value));
    } catch (_) {
      throw FormatException(
        'Unsupported or malformed $kind document; check its schema version.',
      );
    }
  }

  Future<T?> load() => _owner.locked(_read);

  Future<void> save(
    T value, {
    DocumentRevision? expectedRevision,
    bool requireAbsent = false,
  }) {
    // Materialize accepted bytes before awaiting the owner or caller mutation.
    final snapshot = jsonDecode(jsonEncode(encode(value))) as JsonMap;
    decode(snapshot);
    final bytes = (format ?? const JsonEncoder.withIndent('  ').convert)(
      snapshot,
    );
    return _owner.locked(() async {
      await _verify(expectedRevision, requireAbsent: requireAbsent);
      await writeAtomicText(await _checked(), bytes);
    });
  }

  Future<void> delete({DocumentRevision? expectedRevision}) =>
      _owner.locked(() async {
        await _verify(expectedRevision);
        final target = await _checked();
        if (await target.exists()) await target.delete();
      });

  Future<void> _verify(
    DocumentRevision? expected, {
    bool requireAbsent = false,
  }) async {
    final current = await _read();
    if (requireAbsent && current != null ||
        expected != null &&
            (current == null ||
                DocumentRevision.of(encode(current)) != expected)) {
      throw PersistenceConflictException(_name);
    }
  }
}
