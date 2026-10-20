import 'dart:async';
import 'dart:io';

import '../plugins/runtime/provider_operation_policy.dart';
import 'http_policy.dart';

/// Device HTTP ownership and bounds; request paths, certificates, auth headers,
/// response/error mapping and retry decisions stay in their protocol adapters.
Future<T> runProviderHttp<T>({
  required ProviderOperationScope scope,
  required ProviderOperationPolicy policy,
  required Future<T> Function(HttpClient client) send,
  void Function(HttpClient client)? configure,
}) async {
  scope.requireOpen();
  if (policy.requestTimeout <= Duration.zero || policy.maxResponseBytes < 1) {
    throw ArgumentError('Invalid provider HTTP budget.');
  }
  final client = HttpClient()..connectionTimeout = policy.requestTimeout;
  final release = scope.track(() => client.close(force: true));
  try {
    configure?.call(client);
    final value = await send(client).timeout(policy.requestTimeout);
    scope.requireOpen();
    return value;
  } finally {
    release();
    client.close(force: true);
  }
}

Future<String> readProviderHttpText(
  HttpClientResponse response,
  ProviderOperationPolicy policy,
) => readHttpText(response, maxBytes: policy.maxResponseBytes);
