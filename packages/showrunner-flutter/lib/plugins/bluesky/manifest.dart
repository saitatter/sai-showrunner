import 'dart:convert';
import 'dart:io';

import '../../schema/data_input.dart';
import '../../runtime/expression.dart';
import '../registry/plugin_contract.dart';

typedef BlueskyPost =
    Future<RuntimeMap> Function(
      String identifier,
      String appPassword,
      String text,
    );
typedef BlueskyAccountResolver = Future<RuntimeMap?> Function(String id);
typedef BlueskySessionPost =
    Future<RuntimeMap> Function(RuntimeMap session, String text);

final class BlueskyTransport {
  const BlueskyTransport(this.post, {this.postWithSession});

  final BlueskyPost post;
  final BlueskySessionPost? postWithSession;
}

final class BlueskyHttpTransport {
  const BlueskyHttpTransport({this.baseUrl = 'https://bsky.social'});

  final String baseUrl;

  Future<RuntimeMap> login(String identifier, String appPassword) => _request(
    '/xrpc/com.atproto.server.createSession',
    {'identifier': identifier, 'password': appPassword},
  );

  Future<RuntimeMap> post(
    String identifier,
    String appPassword,
    String text,
  ) async {
    final session = await _request('/xrpc/com.atproto.server.createSession', {
      'identifier': identifier,
      'password': appPassword,
    });
    final accessJwt = session['accessJwt']?.toString().trim() ?? '';
    final did = session['did']?.toString().trim() ?? '';
    if (accessJwt.isEmpty || did.isEmpty) {
      throw const FormatException('Bluesky session response is incomplete.');
    }
    final record = await _request('/xrpc/com.atproto.repo.createRecord', {
      'repo': did,
      'collection': 'app.bsky.feed.post',
      'record': {
        r'\$type': 'app.bsky.feed.post',
        'text': text,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      },
    }, accessToken: accessJwt);
    return {...record, 'did': did};
  }

  Future<RuntimeMap> postWithSession(RuntimeMap session, String text) async {
    final accessJwt = session['accessJwt']?.toString().trim() ?? '';
    final did = session['did']?.toString().trim() ?? '';
    if (accessJwt.isEmpty || did.isEmpty) {
      throw const FormatException(
        'Bluesky session credentials are incomplete.',
      );
    }
    final record = await _request('/xrpc/com.atproto.repo.createRecord', {
      'repo': did,
      'collection': 'app.bsky.feed.post',
      'record': {
        r'\$type': 'app.bsky.feed.post',
        'text': text,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      },
    }, accessToken: accessJwt);
    return {...record, 'did': did};
  }

  Future<RuntimeMap> _request(
    String path,
    RuntimeMap body, {
    String? accessToken,
  }) async {
    final uri = Uri.parse(baseUrl).resolve(path);
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      if (accessToken?.isNotEmpty == true) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $accessToken',
        );
      }
      request.write(jsonEncode(body));
      final response = await request.close();
      final responseText = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Bluesky request failed (${response.statusCode}): $responseText',
        );
      }
      if (responseText.isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(responseText);
      return decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } finally {
      client.close(force: true);
    }
  }
}

const _postSchema = DartDataInputSchema(
  label: 'Bluesky post',
  kind: DartDataInputKind.object,
  fields: [
    DartDataInputSchema(
      label: 'Account',
      key: 'account',
      kind: DartDataInputKind.resource,
      resourceType: 'BlueSkyAccount',
    ),
    DartDataInputSchema(
      label: 'Identifier',
      key: 'identifier',
      kind: DartDataInputKind.text,
    ),
    DartDataInputSchema(
      label: 'App password',
      key: 'appPassword',
      kind: DartDataInputKind.text,
      secret: true,
    ),
    DartDataInputSchema(
      label: 'Text',
      key: 'text',
      kind: DartDataInputKind.multilineText,
      required: true,
    ),
  ],
);

DartPluginManifest createBlueskyPlugin(
  BlueskyTransport transport, {
  String? identifier,
  String? appPassword,
  BlueskyAccountResolver? accountResolver,
}) => DartPluginManifest(
  id: 'bluesky',
  name: 'BlueSky',
  settings: const [
    DartSettingDefinition(id: 'identifier', displayName: 'Handle or DID'),
    DartSettingDefinition(
      id: 'appPassword',
      displayName: 'App Password',
      secret: true,
    ),
    DartSettingDefinition(
      id: 'serviceUrl',
      displayName: 'Service URL',
      defaultValue: 'https://bsky.social',
    ),
  ],
  actions: [
    DartActionDefinition(
      pluginId: 'bluesky',
      actionId: 'post',
      displayName: 'BlueSky Post',
      configSchema: _postSchema,
      invoke: (config, context) => _post(
        transport,
        config,
        defaultIdentifier: identifier,
        defaultPassword: appPassword,
        accountResolver: accountResolver,
      ),
    ),
  ],
);

Future<Object?> _post(
  BlueskyTransport transport,
  RuntimeMap config, {
  String? defaultIdentifier,
  String? defaultPassword,
  BlueskyAccountResolver? accountResolver,
}) async {
  final text = config['text']?.toString() ?? '';
  if (text.trim().isEmpty) {
    return {'posted': false, 'text': text, 'reason': 'Post is empty'};
  }
  final accountReference = config['account'];
  final account = accountReference is String && accountResolver != null
      ? await accountResolver(accountReference)
      : accountReference;
  final accountValues = account is Map && account['config'] is Map
      ? account['config'] as Map
      : account is Map
      ? account
      : const <String, dynamic>{};
  final session = accountValues['session'];
  if (session is Map && transport.postWithSession != null) {
    final response = await transport.postWithSession!(
      Map<String, dynamic>.from(session),
      text,
    );
    return {
      'posted': true,
      'text': text,
      if (response['uri'] != null) 'uri': response['uri'],
      if (response['cid'] != null) 'cid': response['cid'],
    };
  }
  final identifier = _firstText([
    config['identifier'],
    accountValues['identifier'],
    defaultIdentifier,
  ]);
  final password = _firstText([
    config['appPassword'],
    accountValues['appPassword'],
    defaultPassword,
  ]);
  if (identifier == null || password == null) {
    return {
      'posted': false,
      'text': text,
      'reason': 'Bluesky account is unconfigured',
    };
  }
  final response = await transport.post(identifier, password, text);
  return {
    'posted': true,
    'text': text,
    if (response['uri'] != null) 'uri': response['uri'],
    if (response['cid'] != null) 'cid': response['cid'],
  };
}

String? _firstText(Iterable<Object?> values) {
  for (final value in values) {
    final text = value?.toString().trim();
    if (text != null && text.isNotEmpty) return text;
  }
  return null;
}
