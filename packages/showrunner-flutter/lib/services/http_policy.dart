import 'dart:convert';
import 'dart:io';

/// Browser requests must address this listener, not a hostname redirected to it.
/// Origin-less OBS/native clients remain supported. This is a browser boundary,
/// not authentication for an explicitly enabled trusted-LAN listener.
Future<Set<String>> trustedHttpHosts(String bindHost) async {
  final Iterable<InternetAddress> addresses =
      bindHost == '0.0.0.0' || bindHost == '::'
      ? (await NetworkInterface.list(
          includeLoopback: true,
        )).expand((network) => network.addresses)
      : await InternetAddress.lookup(bindHost);
  return {
    if (bindHost != '0.0.0.0' && bindHost != '::') bindHost.toLowerCase(),
    if (bindHost == '0.0.0.0' || bindHost == '::')
      Platform.localHostname.toLowerCase(),
    for (final address in addresses) address.address.toLowerCase(),
    if (addresses.any((address) => address.isLoopback)) 'localhost',
  };
}

bool isTrustedHttpRequest(HttpRequest request, {required Set<String> hosts}) {
  final connection = request.connectionInfo;
  final authority = request.headers.value(HttpHeaders.hostHeader);
  if (connection == null || authority == null) return false;
  final target = Uri.tryParse('http://$authority');
  if (target == null ||
      target.userInfo.isNotEmpty ||
      target.path.isNotEmpty ||
      target.hasQuery ||
      target.hasFragment ||
      target.port != connection.localPort) {
    return false;
  }
  if (!hosts.contains(target.host.toLowerCase())) return false;
  final origin = request.headers.value('Origin');
  if (origin != null && origin != target.origin) return false;
  return request.headers.value('Sec-Fetch-Site') != 'cross-site';
}

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
