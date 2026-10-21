/// A secret failure is distinct from a missing file. Its text intentionally
/// excludes cipher/parser exception details, which can contain plaintext.
final class SecretStorageException extends StateError {
  SecretStorageException({required this.owner, required this.operation})
    : super(
        'Encrypted secrets are unavailable for $owner ($operation). Restore secret storage access before saving; existing data was preserved.',
      );
  final String owner;
  final String operation;
}
