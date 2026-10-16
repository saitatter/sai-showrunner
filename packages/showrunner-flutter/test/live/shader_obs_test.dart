import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:showrunner_flutter/plugins/obs/transport.dart';
import 'package:showrunner_flutter/persistence/resource_repository.dart';
import 'package:showrunner_flutter/persistence/viewer_data_repository.dart';
import 'package:showrunner_flutter/plugins/http/manifest.dart';
import 'package:showrunner_flutter/plugins/overlays/manifest.dart';
import 'package:showrunner_flutter/plugins/overlays/websocket_bridge.dart';
import 'package:showrunner_flutter/plugins/overlays/shader_graph/shader_graph.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/variables/manifest.dart';
import 'package:showrunner_flutter/schema/resource.dart';
import 'package:showrunner_flutter/services/plugin_event_hub.dart';

void main() {
  final configPath = Platform.environment['SHOWRUNNER_LIVE_CONFIG'];
  test(
    'compiled shaders animate and receive state bindings in portable OBS',
    () async {
      final owner = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r'$qaSocket=Get-NetTCPConnection -LocalPort 4456 -State Listen -ErrorAction Stop | Select-Object -First 1; (Get-Process -Id $qaSocket.OwningProcess).Path',
      ]);
      final expected = File(
        '.tmp/obs-portable/bin/64bit/obs64.exe',
      ).absolute.path.toLowerCase().replaceAll('\\', '/');
      expect(owner.exitCode, 0);
      expect(
        '${owner.stdout}'.trim().toLowerCase().replaceAll('\\', '/'),
        expected,
        reason: 'Only workspace portable OBS is permitted.',
      );
      final yaml = loadYaml(await File(configPath!).readAsString()) as Map;
      final settings = yaml['plugin_settings']['obs'] as Map;
      expect('${settings['port']}', '4456');
      final password = '${settings['password'] ?? ''}';
      final obs = ObsWebSocketTransport(
        host: '127.0.0.1',
        port: 4456,
        password: password.startsWith('env:')
            ? Platform.environment[password.substring(4)]
            : password,
      );
      final root = await Directory(
        '.tmp/shader-obs-${DateTime.now().millisecondsSinceEpoch}',
      ).create(recursive: true);
      final id = 'shader-proof-${DateTime.now().millisecondsSinceEpoch}';
      final scene = 'ShowRunner $id';
      final source = '$scene Browser';
      final report = <String, Object?>{'portableObsVerified': true};
      final repository = ResourceRepository(Directory('${root.path}/overlays'));
      final store = OverlayResourceStore(
        load: repository.load,
        save: repository.save,
      );
      final hub = DartPluginEventHub();
      final registry = DartPluginRegistry()..register(createVariablesPlugin());
      final server = DartHttpEndpointService(host: '127.0.0.1', port: 0);
      await server.start();
      DartOverlayWebSocketService bridge() => DartOverlayWebSocketService(
        server: server,
        eventHub: hub,
        overlayStore: store,
        registry: registry,
        viewerDataRepository: InMemoryViewerDataRepository(),
      );
      var service = bridge();
      Future<void> save(ShaderDocument graph) async {
        final compiled = compileShaderGraph(graph);
        expect(compiled.errors, isEmpty);
        await repository.save(
          ResourceData(
            id: id,
            config: {
              'name': 'Shader proof',
              'size': {'width': 640, 'height': 360},
              'widgets': [
                {
                  'id': 'shader',
                  'plugin': 'overlays',
                  'widget': 'shaderLayer',
                  'name': 'Shader',
                  'visible': true,
                  'locked': false,
                  'position': {'x': 0, 'y': 0},
                  'size': {'width': 640, 'height': 360},
                  'config': applyCompiledShaderGraph(
                    config: {},
                    graph: graph,
                    glsl: compiled.glsl,
                    uniforms: collectShaderUniformDefaults(graph),
                    bindings: collectShaderUniformBindings(graph),
                  ),
                },
              ],
            },
          ),
        );
        hub.emit(OverlayEventIds.configChanged, {'overlayId': id});
      }

      Future<String> screenshot(String name) async {
        final path = '${root.absolute.path}/$name.png';
        await obs.call('SaveSourceScreenshot', {
          'sourceName': source,
          'imageFormat': 'png',
          'imageFilePath': path,
          'imageWidth': 640,
          'imageHeight': 360,
        });
        return sha256.convert(await File(path).readAsBytes()).toString();
      }

      Future<void> connected() async {
        for (var i = 0; i < 100; i++) {
          if ((await service.getPresence(id)).connected) return;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        fail('Portable browser did not connect.');
      }

      await save(createShaderGraphStarter('energy-field'));
      final original = (await obs.call(
        'GetCurrentProgramScene',
        {},
      ))['currentProgramSceneName'];
      var created = false;
      try {
        await obs.call('CreateScene', {'sceneName': scene});
        created = true;
        await obs.call('CreateInput', {
          'sceneName': scene,
          'inputName': source,
          'inputKind': 'browser_source',
          'inputSettings': {
            'url': service.browserSourceUrl(id),
            'width': 640,
            'height': 360,
            'shutdown': false,
            'restart_when_active': false,
          },
          'sceneItemEnabled': true,
        });
        await obs.call('SetCurrentProgramScene', {'sceneName': scene});
        await connected();
        await Future<void>.delayed(const Duration(seconds: 2));
        final a = await screenshot('energy-1');
        await Future<void>.delayed(const Duration(milliseconds: 700));
        final b = await screenshot('energy-2');
        expect(a, isNot(b));
        report['animatedCompiledShader'] = 'PASS';
        final binding = createShaderDocument(
          nodes: [
            createShaderNode(
              'pulse',
              'uniform_float',
              values: {
                'name': 'pulse',
                'value': '0.2',
                'bindingSource': 'state',
                'bindingPlugin': 'variables',
                'bindingState': 'pulse',
                'bindingPath': 'value',
              },
            ),
            createShaderNode(
              'output',
              'fragment_output',
              values: {'color': 'vec3(1.0)'},
            ),
          ],
          connections: [
            createShaderConnection(
              'alpha',
              'pulse',
              'value',
              'output',
              'alpha',
            ),
          ],
          outputNodeId: 'output',
        );
        registry.updateDynamicState('variables', 'pulse', {'value': 0.2});
        await save(binding);
        await Future<void>.delayed(const Duration(seconds: 1));
        final low = await screenshot('binding-low');
        registry.updateDynamicState('variables', 'pulse', {'value': 0.8});
        await Future<void>.delayed(const Duration(milliseconds: 700));
        final high = await screenshot('binding-high');
        expect(low, isNot(high));
        report['liveStateUniformBinding'] = 'PASS';
        await service.dispose();
        service = bridge();
        await connected();
        await Future<void>.delayed(const Duration(milliseconds: 500));
        registry.updateDynamicState('variables', 'pulse', {'value': 0.4});
        await Future<void>.delayed(const Duration(milliseconds: 700));
        final reconnected = await screenshot('binding-reconnected');
        expect(reconnected, isNot(high));
        expect(reconnected, isNot(low));
        report['bindingAfterBrowserReconnect'] = 'PASS';
        stdout.writeln(
          'PASS actual OBS shader animation, state-bound uniform and reacquisition after reconnect.',
        );
      } finally {
        if (created) {
          await obs.call('SetCurrentProgramScene', {'sceneName': original});
          await obs.call('RemoveScene', {'sceneName': scene});
        }
        await obs.close();
        await service.dispose();
        await server.stop();
        await registry.close();
        await hub.dispose();
        await File(
          '${root.path}/report.json',
        ).writeAsString(jsonEncode(report));
        stdout.writeln('Shader OBS report: ${root.absolute.path}/report.json');
      }
    },
    skip:
        configPath == null ||
        Platform.environment['SHOWRUNNER_SHADER_OBS'] != '1',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
