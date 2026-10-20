import '../../services/http_provider_transports.dart';
import '../runtime/provider_operation_policy.dart';
import 'actions.dart';

typedef TwitchRuntimeRequestFactory =
    TwitchRequest Function({
      required String accessToken,
      required String clientId,
      required ProviderOperationScope scope,
    });

TwitchRequest createTwitchRuntimeRequest({
  required String accessToken,
  required String clientId,
  required ProviderOperationScope scope,
}) => JsonHttpTransport(
  baseUrl: 'https://api.twitch.tv',
  accessToken: accessToken,
  headers: {'Client-Id': clientId},
  operationScope: scope,
).request;
