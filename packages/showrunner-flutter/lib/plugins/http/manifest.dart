import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../components/data_inputs/data_input.dart';
import '../../runtime/expression.dart';
import '../../services/plugin_event_hub.dart';
import '../registry/plugin_registry.dart';

const _endpointPrefix = '/plugins/endpoints';
const _endpointMethods = ['GET', 'POST', 'DELETE', 'PUT', 'PATCH'];

/// Hosts the dynamic HTTP routes used by HTTP endpoint triggers.
///
/// Routes are registered by the profile runtime when a profile containing the
/// trigger becomes active. Cancelling that trigger subscription removes the
/// route, which keeps the server aligned with the active profile set.
final class DartHttpEndpointService {
  DartHttpEndpointService({this.host = '127.0.0.1', this.port = 8181});

  final String host;
  final int port;
  HttpServer? _server;
  final _routes = <_HttpEndpointRoute>[];
  final _requestHandlers = <DartHttpRequestHandler>[];
  final _webSocketHandlers = <DartHttpWebSocketHandler>[];

  int? get boundPort => _server?.port;

  void addRequestHandler(DartHttpRequestHandler handler) {
    _requestHandlers.add(handler);
  }

  void removeRequestHandler(DartHttpRequestHandler handler) {
    _requestHandlers.remove(handler);
  }

  void addWebSocketHandler(DartHttpWebSocketHandler handler) {
    _webSocketHandlers.add(handler);
  }

  void removeWebSocketHandler(DartHttpWebSocketHandler handler) {
    _webSocketHandlers.remove(handler);
  }

  Future<void> start() async {
    if (_server != null) return;
    final server = await HttpServer.bind(host, port);
    _server = server;
    server.listen(_handleRequest);
  }

  Stream<RuntimeMap> register(RuntimeMap config) {
    final method = (config['method']?.toString() ?? 'POST').toUpperCase();
    final route = config['route']?.toString().trim() ?? '';
    if (!_endpointMethods.contains(method)) {
      throw ArgumentError.value(method, 'config.method');
    }
    if (route.isEmpty) {
      throw ArgumentError.value(route, 'config.route');
    }

    late final _HttpEndpointRoute endpoint;
    final controller = StreamController<RuntimeMap>.broadcast(
      sync: true,
      onCancel: () => _routes.remove(endpoint),
    );
    endpoint = _HttpEndpointRoute(
      method: method,
      route: _normalizeRoute(route),
      contextRoute: route,
      controller: controller,
    );
    _routes.add(endpoint);
    return controller.stream;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    final routes = List<_HttpEndpointRoute>.of(_routes);
    _routes.clear();
    for (final route in routes) {
      await route.controller.close();
    }
    await server?.close(force: true);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      final socket = await WebSocketTransformer.upgrade(request);
      for (final handler in List<DartHttpWebSocketHandler>.of(
        _webSocketHandlers,
      )) {
        if (await handler(request, socket)) return;
      }
      await socket.close(WebSocketStatus.normalClosure);
      return;
    }
    for (final handler in List<DartHttpRequestHandler>.of(_requestHandlers)) {
      if (await handler(request)) return;
    }
    final path = request.uri.path;
    if (!path.startsWith('$_endpointPrefix/')) {
      await _respond(request, HttpStatus.notFound);
      return;
    }
    final endpointPath = _normalizeRoute(
      path.substring(_endpointPrefix.length),
    );
    final method = request.method.toUpperCase();
    final matches =
        <({_HttpEndpointRoute route, Map<String, String> params})>[];
    for (final route in List<_HttpEndpointRoute>.of(_routes)) {
      if (route.method != method) continue;
      final params = _matchRoute(route.route, endpointPath);
      if (params != null) matches.add((route: route, params: params));
    }
    if (matches.isEmpty) {
      await _respond(request, HttpStatus.notFound);
      return;
    }

    final body = await _readRequestBody(request);
    final query = <String, dynamic>{
      for (final key in request.uri.queryParametersAll.keys)
        key: request.uri.queryParametersAll[key]!.length == 1
            ? request.uri.queryParametersAll[key]!.single
            : request.uri.queryParametersAll[key],
    };
    for (final match in matches) {
      match.route.controller.add({
        'method': method,
        'route': match.route.contextRoute,
        'params': match.params,
        'query': query,
        'body': body,
      });
    }
    await _respond(request, HttpStatus.created);
  }

  Future<dynamic> _readRequestBody(HttpRequest request) async {
    final raw = await utf8.decoder.bind(request).join();
    if (raw.isEmpty) return <String, dynamic>{};
    final mimeType = request.headers.contentType?.mimeType;
    if (mimeType == 'application/json' || mimeType == 'text/json') {
      try {
        return jsonDecode(raw);
      } on FormatException {
        return raw;
      }
    }
    if (mimeType == 'application/x-www-form-urlencoded') {
      return Uri.splitQueryString(raw);
    }
    return raw;
  }

  Future<void> _respond(HttpRequest request, int statusCode) async {
    request.response
      ..statusCode = statusCode
      ..headers.contentLength = 0;
    await request.response.close();
  }
}

typedef DartHttpRequestHandler = Future<bool> Function(HttpRequest request);
typedef DartHttpWebSocketHandler =
    Future<bool> Function(HttpRequest request, WebSocket socket);

final class _HttpEndpointRoute {
  const _HttpEndpointRoute({
    required this.method,
    required this.route,
    required this.contextRoute,
    required this.controller,
  });

  final String method;
  final String route;
  final String contextRoute;
  final StreamController<RuntimeMap> controller;
}

const _requestSchema = DartDataInputSchema(
  label: 'HTTP request',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'URL',
      key: 'url',
      kind: DartDataInputKind.text,
      required: true,
    ),
    DartDataInputSchema(
      label: 'Method',
      key: 'method',
      kind: DartDataInputKind.enumeration,
      options: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'],
      required: true,
      defaultValue: 'GET',
    ),
    DartDataInputSchema(
      label: 'Query String',
      key: 'query',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      label: 'Content type',
      key: 'contentType',
      kind: DartDataInputKind.enumeration,
      options: [
        'application/json',
        'application/x-www-form-urlencoded',
        'text/plain',
      ],
      defaultValue: 'application/json',
    ),
    DartDataInputSchema(
      label: 'Headers (JSON)',
      key: 'headers',
      kind: DartDataInputKind.multilineText,
    ),
    DartDataInputSchema(
      label: 'Body',
      key: 'body',
      kind: DartDataInputKind.multilineText,
    ),
  ],
);

const _endpointSchema = DartDataInputSchema(
  label: 'HTTP Endpoint',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Method',
      key: 'method',
      kind: DartDataInputKind.enumeration,
      options: _endpointMethods,
      required: true,
      defaultValue: 'POST',
    ),
    DartDataInputSchema(
      label: 'Route',
      key: 'route',
      kind: DartDataInputKind.text,
      required: true,
    ),
  ],
);

DartPluginManifest createHttpPlugin({
  DartPluginEventHub? eventHub,
  DartHttpEndpointService? endpointService,
}) {
  final endpointStream = eventHub?.stream('httpEndpoint');
  return DartPluginManifest(
    id: 'http',
    name: 'HTTP',
    actions: const [
      DartActionDefinition(
        pluginId: 'http',
        actionId: 'request',
        displayName: 'HTTP Request',
        invoke: _httpRequest,
        configSchema: _requestSchema,
      ),
    ],
    triggers: endpointStream == null && endpointService == null
        ? const []
        : [
            DartTriggerDefinition(
              pluginId: 'http',
              triggerId: 'endpoint',
              displayName: 'HTTP Endpoint',
              listen: () => endpointStream ?? const Stream.empty(),
              listenForConfig: endpointService?.register,
              configSchema: _endpointSchema,
              matches: _matchesEndpoint,
            ),
          ],
    start: endpointService?.start,
    stop: endpointService?.stop,
  );
}

Future<Object?> _httpRequest(
  RuntimeMap config,
  EvaluationContext context,
) async {
  final urlStr = config['url']?.toString() ?? '';
  if (urlStr.isEmpty) {
    throw ArgumentError('HTTP request URL is required.');
  }
  final uri = Uri.parse(urlStr);
  final query = config['query']?.toString();
  final requestUri = query == null || query.isEmpty
      ? uri
      : _appendQuery(uri, query);
  final method = (config['method']?.toString() ?? 'GET').toUpperCase();
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, requestUri);
    final contentType = config['contentType']?.toString();
    final body = config['body']?.toString();
    if (body != null &&
        body.isNotEmpty &&
        contentType != null &&
        contentType.isNotEmpty) {
      request.headers.contentType = ContentType.parse(contentType);
    }
    final rawHeaders = config['headers']?.toString();
    if (rawHeaders != null && rawHeaders.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawHeaders);
        if (decoded is! Map) {
          throw FormatException('HTTP headers must be a JSON object.');
        }
        for (final entry in decoded.entries) {
          request.headers.add(entry.key.toString(), entry.value.toString());
        }
      } on FormatException {
        rethrow;
      }
    }
    if (body != null && body.isNotEmpty) {
      request.write(body);
    }
    final response = await request.close();
    final responseBody = await utf8.decoder.bind(response).join();
    final responseContentType = response.headers.contentType?.mimeType;
    if (responseContentType == 'application/json' ||
        responseContentType == 'text/json') {
      try {
        return jsonDecode(responseBody);
      } on FormatException {
        return responseBody;
      }
    }
    return responseBody;
  } finally {
    client.close();
  }
}

Uri _appendQuery(Uri uri, String rawQuery) {
  final extra = Uri.splitQueryString(rawQuery);
  return uri.replace(queryParameters: {...uri.queryParameters, ...extra});
}

bool _matchesEndpoint(RuntimeMap config, RuntimeMap payload) {
  final configuredMethod = config['method']?.toString().toUpperCase();
  final configuredRoute = _normalizeRoute(config['route']?.toString() ?? '');
  return configuredMethod == payload['method'] &&
      configuredRoute == _normalizeRoute(payload['route']?.toString() ?? '');
}

String _normalizeRoute(String route) {
  final trimmed = route.trim();
  if (trimmed.isEmpty) return '/';
  final withLeadingSlash = trimmed.startsWith('/') ? trimmed : '/$trimmed';
  if (withLeadingSlash.length == 1) return withLeadingSlash;
  return withLeadingSlash.replaceFirst(RegExp(r'/+$'), '');
}

Map<String, String>? _matchRoute(String route, String path) {
  final routeSegments = Uri.parse(route).pathSegments;
  final pathSegments = Uri.parse(path).pathSegments;
  if (routeSegments.length != pathSegments.length) return null;
  final params = <String, String>{};
  for (var index = 0; index < routeSegments.length; index++) {
    final expected = routeSegments[index];
    final actual = pathSegments[index];
    if (expected.startsWith(':') && expected.length > 1) {
      params[expected.substring(1)] = actual;
    } else if (expected != actual) {
      return null;
    }
  }
  return params;
}
