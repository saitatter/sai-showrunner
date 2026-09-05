import 'package:flutter_test/flutter_test.dart';
import 'package:showrunner_flutter/plugins/bluesky/manifest.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';

void main() {
  test(
    'posts through the Bluesky transport and returns record identity',
    () async {
      final requests = <({String identifier, String password, String text})>[];
      final registry = DartPluginRegistry()
        ..register(
          createBlueskyPlugin(
            BlueskyTransport((identifier, password, text) async {
              requests.add((
                identifier: identifier,
                password: password,
                text: text,
              ));
              return {
                'uri': 'at://did:plc:test/app.bsky.feed.post/1',
                'cid': 'cid-1',
              };
            }),
          ),
        );

      final result = await registry.invokeAction('bluesky', 'post', {
        'identifier': 'creator.test',
        'appPassword': 'app-password',
        'text': 'Hello from Flutter',
      });

      expect(requests, [
        (
          identifier: 'creator.test',
          password: 'app-password',
          text: 'Hello from Flutter',
        ),
      ]);
      expect(result, {
        'posted': true,
        'text': 'Hello from Flutter',
        'uri': 'at://did:plc:test/app.bsky.feed.post/1',
        'cid': 'cid-1',
      });
    },
  );

  test(
    'uses configured credentials and rejects empty or unconfigured posts',
    () async {
      final requests = <String>[];
      final registry = DartPluginRegistry()
        ..register(
          createBlueskyPlugin(
            BlueskyTransport((identifier, password, text) async {
              requests.add('$identifier:$password:$text');
              return <String, dynamic>{};
            }),
            identifier: 'configured.test',
            appPassword: 'configured-password',
          ),
        );

      final configured = await registry.invokeAction('bluesky', 'post', {
        'text': 'Configured post',
      });
      final empty = await registry.invokeAction('bluesky', 'post', {
        'text': '  ',
      });

      expect(configured, {'posted': true, 'text': 'Configured post'});
      expect(empty, {'posted': false, 'text': '  ', 'reason': 'Post is empty'});
      expect(requests, ['configured.test:configured-password:Configured post']);
    },
  );

  test('resolves credentials from a BlueSky account resource', () async {
    final requests = <String>[];
    final registry = DartPluginRegistry()
      ..register(
        createBlueskyPlugin(
          BlueskyTransport((identifier, password, text) async {
            requests.add('$identifier:$password:$text');
            return <String, dynamic>{};
          }),
        ),
      );

    final result = await registry.invokeAction('bluesky', 'post', {
      'account': {
        'id': 'creator-account',
        'config': {
          'identifier': 'creator.test',
          'appPassword': 'resource-password',
        },
      },
      'text': 'Resource post',
    });

    expect(result, {'posted': true, 'text': 'Resource post'});
    expect(requests, ['creator.test:resource-password:Resource post']);
  });
}
