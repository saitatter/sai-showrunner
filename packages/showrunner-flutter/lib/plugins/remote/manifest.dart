import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../components/data_inputs/data_input.dart';
import '../../services/plugin_event_hub.dart';
import '../registry/plugin_registry.dart';

final class RemoteButtonRuntime {
  RemoteButtonRuntime({
    required this.eventHub,
    this.host = '127.0.0.1',
    this.port = 8390,
  });

  final DartPluginEventHub eventHub;
  final String host;
  final int port;
  HttpServer? _server;
  StreamSubscription<HttpRequest>? _subscription;

  int? get boundPort => _server?.port;

  Future<void> start() async {
    if (_server != null) return;
    _server = await HttpServer.bind(host, port, shared: true);
    _subscription = _server!.listen(_handle);
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      if (request.method == 'GET' && request.uri.path == '/buttons') {
        await _json(request.response, HttpStatus.ok, {'buttons': <String>[]});
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/buttons/press') {
        final name = request.uri.queryParameters['button']?.trim() ?? '';
        if (name.isEmpty) {
          await _json(request.response, HttpStatus.notFound, {});
          return;
        }
        eventHub.emit('remoteButton', {'name': name});
        await _json(request.response, HttpStatus.noContent, null);
        return;
      }
      await _json(request.response, HttpStatus.notFound, {});
    } on Object catch (error) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'error': error.toString()}));
      } on Object {
        // The response may already have started; closing it is still safe.
      }
      try {
        await request.response.close();
      } on Object {
        // Ignore a response that was already closed by the failed write.
      }
    }
  }

  Future<void> _json(HttpResponse response, int status, Object? body) async {
    response.statusCode = status;
    if (body != null) {
      response.headers.contentType = ContentType.json;
      response.write(jsonEncode(body));
    }
    await response.close();
  }
}

const _buttonSchema = DartDataInputSchema(
  label: 'Remote button',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Button name',
      key: 'name',
      kind: DartDataInputKind.text,
      required: true,
    ),
  ],
);

DartPluginManifest createRemotePlugin({
  DartPluginEventHub? eventHub,
  RemoteButtonRuntime? runtime,
}) => DartPluginManifest(
  id: 'remote',
  name: 'Remote',
  settings: const [
    DartSettingDefinition(
      id: 'enabled',
      displayName: 'Enable remote HTTP server',
      defaultValue: false,
    ),
    DartSettingDefinition(
      id: 'host',
      displayName: 'Bind host',
      defaultValue: '127.0.0.1',
    ),
    DartSettingDefinition(
      id: 'port',
      displayName: 'Bind port',
      defaultValue: 8390,
    ),
    DartSettingDefinition(
      id: 'apiBase',
      displayName: 'Remote dashboard API base URL',
      defaultValue: 'https://api.ShowRunner.io',
    ),
  ],
  states: const [
    DartPluginStateDefinition(
      id: 'server',
      displayName: 'Server',
      initialValue: 'stopped',
    ),
  ],
  triggers: eventHub == null
      ? const []
      : [
          DartTriggerDefinition(
            pluginId: 'remote',
            triggerId: 'button',
            displayName: 'Remote Button',
            configSchema: _buttonSchema,
            listen: () => eventHub.stream('remoteButton'),
            matches: (config, payload) =>
                config['name']?.toString() == payload['name']?.toString(),
          ),
        ],
  dispose: runtime?.stop,
);
