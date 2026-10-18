// Opt in with SHOWRUNNER_OBS_FULL_TEST=1 and SHOWRUNNER_LIVE_CONFIG.
// Creates disposable sources/profile, exercises the production graph VM, then
// restores OBS. Never uses the configured public streaming service.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:showrunner_flutter/plugins/obs/actions.dart';
import 'package:showrunner_flutter/plugins/obs/transport.dart';
import 'package:showrunner_flutter/plugins/obs/connection_router.dart';
import 'package:showrunner_flutter/plugins/obs/catalog_runtime.dart';
import 'package:showrunner_flutter/plugins/obs/overlay_source_service.dart';
import 'package:showrunner_flutter/services/showrunner_data_service.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/graph/runtime/graph_execution_engine.dart';
import '../support/graph_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'all OBS actions against disposable live fixtures',
    () async {
      final path = Platform.environment['SHOWRUNNER_LIVE_CONFIG']!;
      Map yaml;
      try {
        yaml = loadYaml(await File(path).readAsString()) as Map;
      } catch (_) {
        fail('Cannot read the local YAML. Credential values are omitted.');
      }
      final settings = yaml['plugin_settings']['obs'] as Map;
      String resolve(Object? value) {
        final s = value?.toString() ?? '';
        return s.startsWith('env:')
            ? Platform.environment[s.substring(4)] ?? ''
            : s;
      }

      final password = resolve(settings['password']);
      String redact(Object error) => '$error'.replaceAll(
        password.isEmpty ? '\u0000' : password,
        '<redacted>',
      );
      final hub = DartPluginEventHub();
      final eventTypes = <String>{};
      final events = hub.stream('obsVendorEvent').listen((event) {
        eventTypes.add('${event['eventType']}');
      });
      final obs = ObsWebSocketTransport(
        host: resolve(settings['host']).isEmpty
            ? '127.0.0.1'
            : resolve(settings['host']),
        port: int.tryParse('${settings['port']}') ?? 4455,
        password: password,
        eventHub: hub,
      );
      final folder = await Directory(
        '.tmp/obs-full-${DateTime.now().millisecondsSinceEpoch}',
      ).create(recursive: true);
      final dataService = ShowRunnerDataService(
        Directory('${folder.path}/app-profile'),
      );
      final router = ObsConnectionRouter(
        dataService: dataService,
        settingsLoader: () async => {'obsDefault': 'qa'},
        resourceLoader: () async => [
          ResourceData(
            id: 'qa',
            config: {
              'name': 'QA',
              'host': obs.host,
              'port': obs.port,
              'password': password,
              'local': true,
            },
          ),
        ],
        transportFactory: (endpoint, onStateChanged) => obs,
      );
      final registry = DartPluginRegistry()..register(createObsPlugin(router));
      final prefix = 'ShowRunner QA ${DateTime.now().millisecondsSinceEpoch}';
      final scene = '$prefix scene';
      final second = '$prefix second';
      final results = <Map<String, Object?>>[];
      final scenes = <String>[];
      bool profileCreated = false;
      final originalProfile = (await obs.call(
        'GetProfileList',
        {},
      ))['currentProfileName'];
      final originalScene = (await obs.call(
        'GetCurrentProgramScene',
        {},
      ))['currentProgramSceneName'];
      final originalStudio = (await obs.call(
        'GetStudioModeEnabled',
        {},
      ))['studioModeEnabled'];
      final originalPreview = originalStudio == true
          ? (await obs.call(
              'GetCurrentPreviewScene',
              {},
            ))['currentPreviewSceneName']
          : null;
      final originalVideo = await obs.call('GetVideoSettings', {});
      final originalParameters = <RuntimeMap>[];
      for (final parameter in [
        ('Output', 'Mode'),
        ('SimpleOutput', 'FilePath'),
        ('AdvOut', 'RecFilePath'),
        ('SimpleOutput', 'RecFormat2'),
        ('SimpleOutput', 'RecQuality'),
        ('SimpleOutput', 'RecEncoder'),
        ('SimpleOutput', 'StreamEncoder'),
        ('SimpleOutput', 'VBitrate'),
        ('SimpleOutput', 'RecRB'),
        ('SimpleOutput', 'RecRBTime'),
        ('SimpleOutput', 'RecRBSize'),
      ]) {
        final query = <String, dynamic>{
          'parameterCategory': parameter.$1,
          'parameterName': parameter.$2,
        };
        final response = await obs.call('GetProfileParameter', query);
        originalParameters.add({
          ...query,
          'parameterValue': response['parameterValue'],
        });
      }
      await File('${folder.path}/restore.json').writeAsString(
        jsonEncode({
          'profile': originalProfile,
          'scene': originalScene,
          'studioMode': originalStudio,
          'preview': originalPreview,
          'video': originalVideo,
          'parameters': originalParameters,
          'temporaryPrefix': prefix,
        }),
      );
      Future<RuntimeMap> call(String name, [RuntimeMap data = const {}]) =>
          obs.call(name, data);
      Future<void> profile(String name) async {
        for (var i = 0; i < 100; i++) {
          if ((await call('GetProfileList'))['currentProfileName'] == name) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        throw StateError('Profile switch did not complete');
      }

      Future<void> mediaState(String source, String expected) async {
        for (var i = 0; i < 50; i++) {
          if ((await call('GetMediaInputStatus', {
                'inputName': source,
              }))['mediaState'] ==
              expected) {
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        throw StateError('Media did not reach $expected');
      }

      Future<RuntimeMap> node(
        String action, [
        RuntimeMap config = const {},
      ]) async {
        final execution = await CompiledExecutionEngine().executeWithRegistry(
          automation: automationFixture(
            entryNodeId: 'obs',
            nodes: [
              GraphNode(
                id: 'obs',
                type: actionNodeType('obs', action),
                data: {'config': config},
              ),
            ],
          ),
          context: EvaluationContext(),
          registry: registry,
        );
        if (!execution.completed) {
          throw StateError('Graph failed: ${execution.nodeResults}');
        }
        return execution.nodeResults['obs'] ?? {};
      }

      Future<void> check(String name, Future<void> Function() body) async {
        try {
          await body();
          results.add({'case': name, 'status': 'PASS'});
        } catch (e) {
          results.add({'case': name, 'status': 'FAIL', 'error': redact(e)});
        }
        stdout.writeln(
          '${results.last['status']} $name${results.last['error'] == null ? '' : ': ${results.last['error']}'}',
        );
      }

      Future<void> waitState(String request, bool active) async {
        for (var i = 0; i < 100; i++) {
          if ((await call(request))['outputActive'] == active) return;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        throw StateError('$request did not become $active');
      }

      Future<void> param(String category, String name, String value) =>
          call('SetProfileParameter', {
            'parameterCategory': category,
            'parameterName': name,
            'parameterValue': value,
          });
      Future<int> input(String name, String kind, RuntimeMap settings) async =>
          (await call('CreateInput', {
                'sceneName': scene,
                'inputName': name,
                'inputKind': kind,
                'inputSettings': settings,
                'sceneItemEnabled': true,
              }))['sceneItemId']
              as int;
      HttpServer? browser;
      try {
        for (final req in [
          'GetStreamStatus',
          'GetRecordStatus',
          'GetVirtualCamStatus',
        ]) {
          if ((await call(req))['outputActive'] == true) {
            throw StateError(
              'Stop active OBS outputs before running this isolated test.',
            );
          }
        }
        try {
          if ((await call('GetReplayBufferStatus'))['outputActive'] == true) {
            throw StateError('Replay buffer must be stopped.');
          }
        } catch (e) {
          if (!'$e'.contains('604')) rethrow;
        }
        await call('CreateProfile', {'profileName': prefix});
        profileCreated = true;
        await profile(prefix);
        await param('Output', 'Mode', 'Simple');
        await param('SimpleOutput', 'RecFormat2', 'hybrid_mp4');
        await param('SimpleOutput', 'RecQuality', 'Small');
        await param('SimpleOutput', 'RecEncoder', 'x264');
        await param('SimpleOutput', 'StreamEncoder', 'x264');
        await param('SimpleOutput', 'VBitrate', '500');
        await param('SimpleOutput', 'RecRB', 'true');
        await param('SimpleOutput', 'RecRBTime', '5');
        await param('SimpleOutput', 'RecRBSize', '50');
        await call('SetRecordDirectory', {
          'recordDirectory': folder.absolute.path,
        });
        // Profile parameters are persisted immediately; output objects are rebuilt
        // on profile activation. Wait for both switches before touching outputs.
        await call('SetCurrentProfile', {'profileName': originalProfile});
        await profile(originalProfile as String);
        await call('SetCurrentProfile', {'profileName': prefix});
        await profile(prefix);
        await call('SetVideoSettings', {
          'baseWidth': 640,
          'baseHeight': 360,
          'outputWidth': 640,
          'outputHeight': 360,
          'fpsNumerator': 30,
          'fpsDenominator': 1,
        });
        for (final name in [scene, second]) {
          await call('CreateScene', {'sceneName': name});
          scenes.add(name);
        }
        await call('SetStudioModeEnabled', {'studioModeEnabled': false});
        await node('scene', {'scene': scene});
        final color = '$prefix color';
        final colorId = await input(color, 'color_source_v3', {
          'width': 320,
          'height': 180,
          'color': 0xff4080ff,
        });
        final imagePath = '${folder.absolute.path}/fixture.png';
        await call('SaveSourceScreenshot', {
          'sourceName': color,
          'imageFormat': 'png',
          'imageFilePath': imagePath,
        });
        final image = '$prefix image';
        await input(image, 'image_source', {'file': imagePath});
        final text = '$prefix text';
        await input(text, 'text_gdiplus_v3', {'text': 'fixture'});
        browser = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var browserRequests = 0;
        browser.listen((request) {
          browserRequests++;
          request.response.headers.contentType = ContentType.html;
          request.response.write(
            '<body style="background:#234">ShowRunner OBS QA</body>',
          );
          request.response.close();
        });
        final url = 'http://127.0.0.1:${browser.port}/';
        final web = '$prefix browser';
        await input(web, 'browser_source', {
          'url': url,
          'width': 320,
          'height': 180,
        });
        final wav = ByteData(44 + 16000 * 10 * 2);
        void ascii(int offset, String value) {
          for (var i = 0; i < value.length; i++) {
            wav.setUint8(offset + i, value.codeUnitAt(i));
          }
        }

        ascii(0, 'RIFF');
        wav.setUint32(4, wav.lengthInBytes - 8, Endian.little);
        ascii(8, 'WAVEfmt ');
        wav.setUint32(16, 16, Endian.little);
        wav.setUint16(20, 1, Endian.little);
        wav.setUint16(22, 1, Endian.little);
        wav.setUint32(24, 16000, Endian.little);
        wav.setUint32(28, 32000, Endian.little);
        wav.setUint16(32, 2, Endian.little);
        wav.setUint16(34, 16, Endian.little);
        ascii(36, 'data');
        wav.setUint32(40, wav.lengthInBytes - 44, Endian.little);
        final mediaPath = '${folder.absolute.path}/silence.wav';
        await File(mediaPath).writeAsBytes(wav.buffer.asUint8List());
        final media = '$prefix media';
        final mediaId = await input(media, 'ffmpeg_source', {
          'local_file': mediaPath,
          'is_local_file': true,
          'looping': true,
        });
        final playlist = '$prefix playlist';
        await input(playlist, 'vlc_source', {
          'playlist': [
            {'value': mediaPath, 'hidden': false},
            {'value': mediaPath, 'hidden': false},
          ],
          'loop': true,
        });
        await call('CreateSourceFilter', {
          'sourceName': color,
          'filterName': 'QA filter',
          'filterKind': 'color_filter_v2',
          'filterSettings': {},
        });
        await check('OBS workspace live scene/source/filter catalog', () async {
          final catalog = await ObsCatalogService(
            dataService: dataService,
            call: obs.call,
          ).load();
          expect(catalog.scenes, contains(scene));
          expect(
            catalog.itemsByScene[scene]!.any((item) => item.id == colorId),
            true,
          );
          expect(catalog.filtersBySource[color]!.single.name, 'QA filter');
          expect(catalog.inputKindsByName[web], 'browser_source');
        });
        await check(
          'overlay OBS browser source inspect / create / fix',
          () async {
            final service = OverlayObsSourceService(
              dataService: dataService,
              router: router,
            );
            final overlay = '$prefix overlay';
            final sourceName = '$prefix overlay source';
            Future<OverlayBrowserSourceStatus> inspect() => service.inspect(
              connectionId: 'qa',
              overlayId: overlay,
              width: 320,
              height: 180,
              port: browser!.port,
            );
            expect((await service.listConnections()).single.id, 'qa');
            expect((await inspect()).needsCreate, true);
            await service.createBrowserSource(
              connectionId: 'qa',
              overlayId: overlay,
              sourceName: sourceName,
              width: 320,
              height: 180,
              port: browser!.port,
            );
            expect((await inspect()).isCurrent, true);
            await call('SetInputSettings', {
              'inputName': sourceName,
              'inputSettings': {'width': 640},
            });
            expect((await inspect()).needsFix, true);
            await service.fixBrowserSource(
              connectionId: 'qa',
              overlayId: overlay,
              sourceName: sourceName,
              width: 320,
              height: 180,
              port: browser!.port,
            );
            expect((await inspect()).isCurrent, true);
          },
        );
        await check('scene / prevScene', () async {
          await node('scene', {'scene': second});
          expect(
            (await call('GetCurrentProgramScene'))['currentProgramSceneName'],
            second,
          );
          await node('prevScene');
          expect(
            (await call('GetCurrentProgramScene'))['currentProgramSceneName'],
            scene,
          );
        });
        await check('getInputSettings / setInputSettings / text', () async {
          await node('setInputSettings', {
            'sourceName': text,
            'inputSettings': {'text': 'settings'},
          });
          expect(
            ((await node('getInputSettings', {
                  'sourceName': text,
                }))['inputSettings']
                as Map)['text'],
            'settings',
          );
          await node('text', {'sourceName': text, 'text': 'Romanian: șțăîâ'});
          expect(
            ((await call('GetInputSettings', {
                  'inputName': text,
                }))['inputSettings']
                as Map)['text'],
            'Romanian: șțăîâ',
          );
        });
        for (final action in ['source', 'filter', 'mute']) {
          await check('$action true / false / toggle twice', () async {
            final field = action == 'source'
                ? 'enabled'
                : action == 'filter'
                ? 'filterEnabled'
                : 'muted';
            final config = action == 'source'
                ? {'scene': scene, 'source': colorId}
                : action == 'filter'
                ? {'sourceName': color, 'filterName': 'QA filter'}
                : {'source': media};
            var expected = false;
            for (final value in [true, false, 'toggle', 'toggle']) {
              expected = value == 'toggle' ? !expected : value == true;
              await node(action, {...config, field: value});
              final state = action == 'source'
                  ? (await call('GetSceneItemEnabled', {
                      'sceneName': scene,
                      'sceneItemId': colorId,
                    }))['sceneItemEnabled']
                  : action == 'filter'
                  ? (await call('GetSourceFilter', {
                      'sourceName': color,
                      'filterName': 'QA filter',
                    }))['filterEnabled']
                  : (await call('GetInputMute', {
                      'inputName': media,
                    }))['inputMuted'];
              expect(state, expected);
            }
            final last = action == 'mute'
                ? (await call('GetInputMute', {
                    'inputName': media,
                  }))['inputMuted']
                : action == 'source'
                ? (await call('GetSceneItemEnabled', {
                    'sceneName': scene,
                    'sceneItemId': colorId,
                  }))['sceneItemEnabled']
                : (await call('GetSourceFilter', {
                    'sourceName': color,
                    'filterName': 'QA filter',
                  }))['filterEnabled'];
            expect(last, false);
          });
        }
        await check('changeVolume 0 / 50 / 100', () async {
          for (final volume in [0, 50, 100]) {
            await node('changeVolume', {'source': media, 'volume': volume});
            // Preserve the existing OBS fader curve (50 is not linear amplitude).
            final db = volume == 0
                ? -100
                : volume == 100
                ? 0
                : -102 * math.pow(17, -volume / 100) + 6;
            expect(
              (await call('GetInputVolume', {
                'inputName': media,
              }))['inputVolumeDb'],
              closeTo(db, 0.001),
            );
          }
        });
        await check('setImage / screenshot', () async {
          await node('setImage', {'sourceName': image, 'image': imagePath});
          final result = await node('screenshot', {
            'sourceName': image,
            'directory': folder.absolute.path,
            'filename': 'node-capture',
            'width': 160,
            'height': 90,
          });
          expect(
            await File(result['screenshot'] as String).length(),
            greaterThan(64),
          );
          expect(
            ((await call('GetInputSettings', {
                  'inputName': image,
                }))['inputSettings']
                as Map)['file'],
            imagePath,
          );
        });
        await check('transform', () async {
          await node('transform', {
            'scene': scene,
            'source': colorId,
            'transform': {
              'position': {'x': 32, 'y': 48},
              'rotation': 15,
              'scale': {'x': 0.5, 'y': 0.75},
              'crop': {'left': 2, 'top': 3, 'right': 4, 'bottom': 5},
            },
          });
          final t =
              (await call('GetSceneItemTransform', {
                    'sceneName': scene,
                    'sceneItemId': colorId,
                  }))['sceneItemTransform']
                  as Map;
          expect(t['positionX'], 32);
          expect(t['rotation'], 15);
          expect(t['cropLeft'], 2);
        });
        for (final action in [
          'browserUrl',
          'setBrowserURL',
          'browserRefresh',
          'refreshBrowser',
        ]) {
          await check(action, () async {
            final isLegacy =
                action == 'browserUrl' || action == 'browserRefresh';
            final refresh = action.toLowerCase().contains('refresh');
            final before = browserRequests;
            await node(action, {
              isLegacy ? 'source' : 'sourceName': web,
              if (!refresh) 'url': '$url?action=$action',
            });
            for (var i = 0; i < 50 && browserRequests <= before; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            expect(browserRequests, greaterThan(before));
          });
        }
        await check('playMedia public scene-item configuration', () async {
          await call('SetSceneItemEnabled', {
            'sceneName': scene,
            'sceneItemId': mediaId,
            'sceneItemEnabled': false,
          });
          await node('playMedia', {'scene': scene, 'source': mediaId});
          await mediaState(media, 'OBS_MEDIA_STATE_PLAYING');
        });
        for (final action in [
          'Play',
          'Pause',
          'Restart',
          'Stop',
          'Next',
          'Previous',
        ]) {
          await check('mediaAction $action', () async {
            await node('mediaAction', {
              'source': action == 'Next' || action == 'Previous'
                  ? playlist
                  : media,
              'action': action,
            });
            if (action != 'Next' && action != 'Previous') {
              await mediaState(
                media,
                action == 'Pause'
                    ? 'OBS_MEDIA_STATE_PAUSED'
                    : action == 'Stop'
                    ? 'OBS_MEDIA_STATE_STOPPED'
                    : 'OBS_MEDIA_STATE_PLAYING',
              );
            }
          });
        }
        await check('recordingStartStop / chapterMarker', () async {
          await node('recordingStartStop', {'recording': true});
          await waitState('GetRecordStatus', true);
          await Future<void>.delayed(const Duration(seconds: 2));
          await node('chapterMarker', {'chapterName': 'ShowRunner QA chapter'});
          await node('recordingStartStop', {'recording': 'toggle'});
          await waitState('GetRecordStatus', false);
          expect(
            folder.listSync().whereType<File>().any(
              (f) => f.path.endsWith('.mp4') && f.lengthSync() > 0,
            ),
            true,
          );
        });
        await check('replayBufferStartStop / replaySave', () async {
          await node('replayBufferStartStop', {'replayBuffer': true});
          await waitState('GetReplayBufferStatus', true);
          await Future<void>.delayed(const Duration(seconds: 3));
          final replay = await node('replaySave');
          expect(replay['replayFile'], isA<String>());
          expect(await File(replay['replayFile'] as String).exists(), true);
          await node('replayBufferStartStop', {'replayBuffer': 'toggle'});
          await waitState('GetReplayBufferStatus', false);
        });
        await check('virtualCamStartStop true / toggle', () async {
          await node('virtualCamStartStop', {'virtualCam': true});
          await waitState('GetVirtualCamStatus', true);
          await node('virtualCamStartStop', {'virtualCam': 'toggle'});
          await waitState('GetVirtualCamStatus', false);
        });
        final rtmp = Platform.environment['SHOWRUNNER_OBS_LOCAL_RTMP'];
        await check('streamStartStop local RTMP true / toggle', () async {
          if (rtmp == null ||
              !RegExp(r'^rtmp://127\.0\.0\.1:\d+/').hasMatch(rtmp)) {
            throw StateError(
              'Local RTMP receiver required: SHOWRUNNER_OBS_LOCAL_RTMP=rtmp://127.0.0.1:PORT/live',
            );
          }
          await call('SetStreamServiceSettings', {
            'streamServiceType': 'rtmp_custom',
            'streamServiceSettings': {
              'server': rtmp,
              'key': 'showrunner-qa',
              'use_auth': false,
            },
          });
          await node('streamStartStop', {'streaming': true});
          await waitState('GetStreamStatus', true);
          await Future<void>.delayed(const Duration(seconds: 2));
          expect(
            (await call('GetStreamStatus'))['outputBytes'],
            greaterThan(0),
          );
          await node('streamStartStop', {'streaming': 'toggle'});
          await waitState('GetStreamStatus', false);
        });
        if (Platform.environment['SHOWRUNNER_OBS_SKIP_STUDIO'] != '1') {
          await check('toggleStudioMode true / false / toggle twice', () async {
            for (final pair in [
              (true, true),
              (false, false),
              ('toggle', true),
              ('toggle', false),
            ]) {
              await node('toggleStudioMode', {'studioMode': pair.$1});
              expect(
                (await call('GetStudioModeEnabled'))['studioModeEnabled'],
                pair.$2,
              );
              await Future<void>.delayed(const Duration(milliseconds: 500));
            }
          });
          await check('triggerStudioModeTransition', () async {
            await call('SetStudioModeEnabled', {'studioModeEnabled': true});
            await Future<void>.delayed(const Duration(milliseconds: 500));
            await call('SetCurrentPreviewScene', {'sceneName': second});
            await Future<void>.delayed(const Duration(milliseconds: 500));
            await node('triggerStudioModeTransition');
            await Future<void>.delayed(const Duration(seconds: 1));
            expect(
              (await call('GetCurrentProgramScene'))['currentProgramSceneName'],
              second,
            );
            await call('SetStudioModeEnabled', {'studioModeEnabled': false});
            await Future<void>.delayed(const Duration(milliseconds: 500));
            await call('SetCurrentProgramScene', {'sceneName': scene});
          });
        }
        await check('hotkey start / stop virtual camera', () async {
          await node('hotkey', {'hotkey': 'OBSBasic.StartVirtualCam'});
          await waitState('GetVirtualCamStatus', true);
          await node('hotkey', {'hotkey': 'OBSBasic.StopVirtualCam'});
          await waitState('GetVirtualCamStatus', false);
        });
        await check('OBS vendor events delivered to trigger hub', () async {
          expect(
            eventTypes,
            containsAll([
              'CurrentProgramSceneChanged',
              'RecordStateChanged',
              'ReplayBufferSaved',
              'StreamStateChanged',
            ]),
          );
        });
      } finally {
        // Continue cleanup after any individual failure, and report every failure.
        var connectionLost = false;
        Future<void> restore(String label, String req, RuntimeMap data) async {
          if (connectionLost) return;
          try {
            await call(req, data);
          } catch (e) {
            connectionLost =
                e is SocketException || '$e'.contains('connection');
            results.add({
              'case': 'cleanup $label',
              'status': 'FAIL',
              'error': redact(e),
            });
          }
        }

        if (profileCreated) {
          for (final pair in [
            ('GetStreamStatus', 'StopStream'),
            ('GetRecordStatus', 'StopRecord'),
            ('GetVirtualCamStatus', 'StopVirtualCam'),
            ('GetReplayBufferStatus', 'StopReplayBuffer'),
          ]) {
            if (connectionLost) break;
            try {
              if ((await call(pair.$1))['outputActive'] == true) {
                await call(pair.$2);
                await waitState(pair.$1, false);
              }
            } catch (e) {
              connectionLost =
                  e is SocketException || '$e'.contains('connection');
              if (!'$e'.contains('604')) {
                results.add({
                  'case': 'cleanup outputs',
                  'status': 'FAIL',
                  'error': redact(e),
                });
              }
            }
          }
          await restore('studio off', 'SetStudioModeEnabled', {
            'studioModeEnabled': false,
          });
          await Future<void>.delayed(const Duration(milliseconds: 500));
          await restore('program', 'SetCurrentProgramScene', {
            'sceneName': originalScene,
          });
          for (final name in scenes.reversed) {
            await restore(name, 'RemoveScene', {'sceneName': name});
          }
          await restore('profile', 'SetCurrentProfile', {
            'profileName': originalProfile,
          });
          if (!connectionLost) {
            await check(
              'cleanup original profile ready',
              () => profile(originalProfile as String),
            );
          }
          for (final parameter in originalParameters) {
            await restore(
              'original parameter',
              'SetProfileParameter',
              parameter,
            );
          }
          await restore('temporary profile', 'RemoveProfile', {
            'profileName': prefix,
          });
          await restore('video', 'SetVideoSettings', {
            for (final key in [
              'baseWidth',
              'baseHeight',
              'outputWidth',
              'outputHeight',
              'fpsNumerator',
              'fpsDenominator',
            ])
              key: originalVideo[key],
          });
          await restore('studio', 'SetStudioModeEnabled', {
            'studioModeEnabled': originalStudio,
          });
          if (originalPreview != null) {
            await restore('preview', 'SetCurrentPreviewScene', {
              'sceneName': originalPreview,
            });
          }
        }
        await browser?.close(force: true);
        await File('${folder.path}/report.json').writeAsString(
          const JsonEncoder.withIndent('  ').convert({'results': results}),
        );
        stdout.writeln('Report: ${folder.absolute.path}/report.json');
        await registry.close();
        await obs.close();
        await events.cancel();
        await hub.dispose();
      }
      expect(results.where((r) => r['status'] == 'FAIL').toList(), isEmpty);
    },
    skip: Platform.environment['SHOWRUNNER_OBS_FULL_TEST'] != '1',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
