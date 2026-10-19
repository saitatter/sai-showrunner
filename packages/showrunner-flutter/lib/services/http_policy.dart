import 'dart:convert';

final class HttpBodyLimitException implements Exception {
  const HttpBodyLimitException({this.responseSent = false});
  final bool responseSent;
  @override
  String toString() => 'HTTP body exceeds the configured size limit.';
}

Future<String> readHttpText(
  Stream<List<int>> body, {
  required int maxBytes,
  Future<void> Function()? onLimit,
}) async {
  final bytes = <int>[];
  await for (final chunk in body) {
    if (bytes.length + chunk.length > maxBytes) {
      if (onLimit != null) await onLimit();
      throw HttpBodyLimitException(responseSent: onLimit != null);
    }
    bytes.addAll(chunk);
  }
  return utf8.decode(bytes);
}

final class ProviderRateLimitException implements Exception {
  ProviderRateLimitException({String? retryAfter})
    : delay = Duration(
        seconds: (int.tryParse(retryAfter ?? '') ?? 1).clamp(0, 5),
      );
  final Duration delay;
  @override
  String toString() => 'The provider rate limit was reached. Retry later.';
}
