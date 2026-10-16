// Owner-authorized temporary title update and read-only capability checks.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:showrunner_flutter/plugins/twitch/actions.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/services/http_provider_transports.dart';

void main() {
  final configPath = Platform.environment['SHOWRUNNER_LIVE_CONFIG'];
  test(
    'live stream info round trip and channel capability checks',
    () async {
      final yaml = loadYaml(await File(configPath!).readAsString()) as Map;
      final settings = yaml['plugin_settings']['twitch'] as Map;
      String value(String key) {
        final v = '${settings[key] ?? ''}';
        return v.startsWith('env:')
            ? Platform.environment[v.substring(4)] ?? ''
            : v;
      }

      final channel = value('broadcasterId');
      final http = JsonHttpTransport(
        baseUrl: 'https://api.twitch.tv',
        accessToken: value('accessToken'),
        headers: {'Client-Id': value('clientId')},
      );
      final registry = DartPluginRegistry()
        ..register(
          createTwitchPlugin(
            TwitchTransport.withDefaults(
              http.request,
              broadcasterId: channel,
              moderatorId: channel,
            ),
          ),
        );
      final directory = await Directory(
        '.tmp/twitch-actions-${DateTime.now().millisecondsSinceEpoch}',
      ).create(recursive: true);
      final report = <String, Object?>{};
      Future<Map> info() async =>
          ((await http.request('GET', '/helix/channels', {
                        'broadcaster_id': channel,
                      }, {}))['data']
                      as List)
                  .single
              as Map;
      final original = await info();
      var restoreTitle = false;
      try {
        final user =
            ((await http.request('GET', '/helix/users', {
                          'id': channel,
                        }, {}))['data']
                        as List)
                    .single
                as Map;
        report['broadcasterType'] = user['broadcaster_type'];
        report['isLive'] =
            ((await http.request('GET', '/helix/streams', {
                      'user_id': channel,
                    }, {}))['data']
                    as List)
                .isNotEmpty;
        for (final feature in {
          'rewards': '/helix/channel_points/custom_rewards',
          'polls': '/helix/polls',
          'predictions': '/helix/predictions',
          'ads': '/helix/channels/ads',
        }.entries) {
          try {
            await http.request('GET', feature.value, {
              'broadcaster_id': channel,
            }, {});
            report[feature.key] = 'read accepted';
          } on HttpException catch (error) {
            report[feature.key] = error.message;
          }
        }
        restoreTitle = true;
        final title = 'ShowRunner QA ${DateTime.now().millisecondsSinceEpoch}';
        await registry.invokeAction('twitch', 'setStreamInfo', {
          'title': title,
        });
        expect((await info())['title'], title);
        report['setStreamInfo'] = 'PASS';
        stdout.writeln('PASS stream title write and read-back.');
      } finally {
        try {
          if (restoreTitle) {
            await registry.invokeAction('twitch', 'setStreamInfo', {
              'title': original['title'],
            });
            expect((await info())['title'], original['title']);
            report['originalTitleRestored'] = true;
          }
        } finally {
          await registry.close();
          await File(
            '${directory.path}/report.json',
          ).writeAsString(const JsonEncoder.withIndent('  ').convert(report));
          stdout.writeln(
            'Capabilities (no credentials): ${jsonEncode(report)}',
          );
          stdout.writeln('Report: ${directory.absolute.path}/report.json');
        }
      }
    },
    skip:
        configPath == null ||
        Platform.environment['SHOWRUNNER_TWITCH_MUTATIONS'] != '1',
  );
}
