import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

final class HttpRequestConfig {
  const HttpRequestConfig({
    this.url,
    this.method,
    this.query,
    this.contentType,
    this.headers,
    this.body,
  });

  factory HttpRequestConfig.fromRuntime(RuntimeMap value) => HttpRequestConfig(
    url: _string(value['url']),
    method: _string(value['method']),
    query: _string(value['query']),
    contentType: _string(value['contentType']),
    headers: _string(value['headers']),
    body: _string(value['body']),
  );

  final String? url;
  final String? method;
  final String? query;
  final String? contentType;
  final String? headers;
  final String? body;

  RuntimeMap toRuntime() => {
    if (url != null) 'url': url,
    if (method != null) 'method': method,
    if (query != null) 'query': query,
    if (contentType != null) 'contentType': contentType,
    if (headers != null) 'headers': headers,
    if (body != null) 'body': body,
  };
}

final class HttpConfigCodec<C> implements PluginConfigCodec<C> {
  const HttpConfigCodec(this._decoder, this._encoder);

  final C Function(RuntimeMap) _decoder;
  final RuntimeMap Function(C value) _encoder;

  @override
  C decode(RuntimeMap value) => _decoder(value);

  @override
  RuntimeMap encode(C value) => _encoder(value);
}

final httpRequestConfigCodec = HttpConfigCodec(
  HttpRequestConfig.fromRuntime,
  (HttpRequestConfig value) => value.toRuntime(),
);

final class HttpEndpointConfig {
  const HttpEndpointConfig({this.method = 'POST', this.route});

  factory HttpEndpointConfig.fromRuntime(RuntimeMap value) =>
      HttpEndpointConfig(
        method: _string(value['method']) ?? 'POST',
        route: _string(value['route']),
      );

  final String method;
  final String? route;

  RuntimeMap toRuntime() => {
    'method': method,
    if (route != null) 'route': route,
  };
}

final httpEndpointConfigCodec = HttpConfigCodec(
  HttpEndpointConfig.fromRuntime,
  (HttpEndpointConfig value) => value.toRuntime(),
);

String? _string(Object? value) => value?.toString();
