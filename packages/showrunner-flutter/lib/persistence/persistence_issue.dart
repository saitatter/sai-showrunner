import 'dart:io';
import 'filesystem/file_transaction.dart';
import 'secret_storage_exception.dart';

enum PersistenceIssueKind {
  invalidDocument,
  unsupportedDocument,
  secretUnavailable,
  io,
  conflict,
  unsafePath,
}

/// Safe diagnostic metadata; never retains parser source or decoded values.
final class PersistenceIssue {
  const PersistenceIssue({
    required this.owner,
    required this.document,
    required this.kind,
  });
  final String owner;
  final String document;
  final PersistenceIssueKind kind;
  factory PersistenceIssue.fromError(
    Object error, {
    required String owner,
    required String document,
  }) => PersistenceIssue(
    owner: owner,
    document: document,
    kind: switch (error) {
      SecretStorageException() => PersistenceIssueKind.secretUnavailable,
      PersistenceConflictException() => PersistenceIssueKind.conflict,
      FileSystemException() => PersistenceIssueKind.io,
      ArgumentError() => PersistenceIssueKind.unsafePath,
      FormatException() when error.message.startsWith('Unsupported') =>
        PersistenceIssueKind.unsupportedDocument,
      _ => PersistenceIssueKind.invalidDocument,
    },
  );
  String get message => switch (kind) {
    PersistenceIssueKind.secretUnavailable =>
      'Encrypted credentials are unavailable. Restore access before editing.',
    PersistenceIssueKind.conflict =>
      'Stored data changed. Reload and resolve the pending conflict.',
    PersistenceIssueKind.io =>
      'Storage could not be read. Check filesystem access and retry.',
    PersistenceIssueKind.unsafePath =>
      'The storage path is unsafe or leaves the application directory.',
    PersistenceIssueKind.unsupportedDocument =>
      'The document format is unsupported. Inspect its stored file before editing.',
    PersistenceIssueKind.invalidDocument =>
      'The document is malformed. Inspect and repair its stored file before editing.',
  };
  @override
  String toString() => '$owner/$document: $message';
}
