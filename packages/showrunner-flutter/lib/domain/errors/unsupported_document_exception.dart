/// A known document envelope/schema is newer or outside the supported contract.
/// No source text, credentials or raw decoder exceptions are retained.
final class UnsupportedDocumentException extends FormatException {
  const UnsupportedDocumentException(super.message);
}
