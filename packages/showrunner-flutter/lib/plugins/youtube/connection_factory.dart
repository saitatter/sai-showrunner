import '../../services/http_provider_transports.dart';
import '../runtime/provider_operation_policy.dart';
import 'actions.dart';

typedef YouTubeRuntimeRequestFactory =
    YouTubeRequest Function({
      required String accessToken,
      required ProviderOperationScope scope,
    });

YouTubeRequest createYouTubeRuntimeRequest({
  required String accessToken,
  required ProviderOperationScope scope,
}) => JsonHttpTransport(
  baseUrl: 'https://www.googleapis.com',
  accessToken: accessToken,
  operationScope: scope,
).request;
