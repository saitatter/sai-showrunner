import 'dart:convert';
import 'package:crypto/crypto.dart';

/// An in-memory semantic fingerprint; never serialized into authoring data.
final class DocumentRevision {
  DocumentRevision.of(Object? document)
    : _digest = sha256
          .convert(utf8.encode(jsonEncode(_ordered(document))))
          .toString();
  final String _digest;
  @override
  bool operator ==(Object other) =>
      other is DocumentRevision && other._digest == _digest;
  @override
  int get hashCode => _digest.hashCode;
  @override
  String toString() => 'DocumentRevision';
}

Object? _ordered(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _ordered(value[key])};
  }
  if (value is List) return value.map(_ordered).toList();
  return value;
}
