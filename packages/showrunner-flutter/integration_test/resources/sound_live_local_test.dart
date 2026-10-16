import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:showrunner_flutter/plugins/registry/plugin_registry.dart';
import 'package:showrunner_flutter/plugins/sound/manifest.dart';
import 'package:showrunner_flutter/plugins/sound/output.dart';
import 'package:showrunner_flutter/plugins/sound/tts_runtime.dart';
import 'package:showrunner_flutter/plugins/sound/windows_audio.dart';
import 'package:showrunner_flutter/runtime/expression.dart';
import 'package:showrunner_flutter/runtime/graph_execution_engine.dart';
import 'package:showrunner_flutter/schema/automation.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test(
    'real Windows TTS, default playback, trim, splitter, missing output and abort',
    () async {
      MediaKit.ensureInitialized();
      final root = await Directory.systemTemp.createTemp(
        'showrunner-sound-proof-',
      );
      addTearDown(() => root.delete(recursive: true));
      final synth = WindowsTtsFileSynthesisService(cacheDirectory: root);
      final file = await synth.synthesizeToFile(
        const TtsSpeechRequest(text: 'ShowRunner audio test', volume: 0.2),
      );
      expect(file, isNotNull);
      expect(await File(file!).length(), greaterThan(44));
      final outputs = createDefaultSoundOutputRegistry();
      expect(outputs.find('system.default'), isNotNull);
      outputs.registerSplitter('qa-splitter', const [
        AudioSplitterRedirect(output: 'system.default', volume: 30),
      ]);
      final registry = DartPluginRegistry()
        ..register(
          createSoundPlugin(
            ttsFileService: synth,
            soundOutputs: outputs,
            globalVolume: 20,
          ),
        );
      addTearDown(registry.close);
      Future<Map> graph(String action, Map<String, dynamic> config) async {
        final result = await CompiledExecutionEngine().executeWithRegistry(
          automation: AutomationData(
            graph: AutomationGraph(
              entryNodeId: 'audio',
              nodes: [
                GraphNode(
                  id: 'audio',
                  type: 'action',
                  x: 0,
                  y: 0,
                  data: {'plugin': 'sound', 'action': action, 'config': config},
                ),
              ],
              edges: const [],
            ),
          ),
          context: EvaluationContext(),
          registry: registry,
        );
        expect(result.completed, true);
        return result.nodeResults['audio'] as Map;
      }

      expect(
        (await graph('sound', {
          'sound': file,
          'volume': 25,
          'startTime': 0.05,
          'endTime': 0.3,
        }))['played'],
        true,
      );
      final conversions = <String>[];
      final ffmpeg = await Process.run('where.exe', ['ffmpeg']);
      if (ffmpeg.exitCode == 0) {
        final executable = '${ffmpeg.stdout}'
            .trim()
            .split(RegExp(r'\r?\n'))
            .first;
        for (final extension in ['mp3', 'ogg', 'flac']) {
          final converted = '${root.path}/speech.$extension';
          final conversion = await Process.run(executable, [
            '-hide_banner',
            '-loglevel',
            'error',
            '-i',
            file,
            converted,
          ]);
          expect(conversion.exitCode, 0);
          expect(
            (await graph('sound', {
              'sound': converted,
              'volume': 5,
              'endTime': 0.25,
            }))['played'],
            true,
          );
          conversions.add(extension);
        }
      }
      stdout.writeln('Real additional audio formats: $conversions');
      expect(
        (await graph('tts', {
          'text': 'ShowRunner speech test',
          'output': 'qa-splitter',
          'volume': 25,
        }))['spoken'],
        true,
      );
      expect(
        (await graph('sound', {
          'sound': file,
          'output': 'not-a-device',
        }))['played'],
        false,
      );
      final tone = File('${root.path}/long.wav');
      await tone.writeAsBytes(_tone());
      final watch = Stopwatch()..start();
      final playing = outputs.playFile(
        file: tone.path,
        volume: 1,
        playId: 'qa-abort',
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await outputs.abortPlay('qa-abort');
      await playing.timeout(const Duration(seconds: 3));
      expect(watch.elapsed, lessThan(const Duration(seconds: 4)));
      stdout.writeln(
        'PASS real system TTS WAV, trimmed playback, TTS graph through splitter, missing output, and cancellation.',
      );
    },
    skip: Platform.environment['SHOWRUNNER_LOCAL_AUDIO'] != '1',
    timeout: const Timeout(Duration(seconds: 50)),
  );
}

Uint8List _tone() {
  const samples = 22050 * 8;
  final bytes = Uint8List(44 + samples * 2);
  final d = ByteData.sublistView(bytes);
  void chars(int at, String value) {
    bytes.setRange(at, at + value.length, value.codeUnits);
  }

  chars(0, 'RIFF');
  d.setUint32(4, bytes.length - 8, Endian.little);
  chars(8, 'WAVE');
  chars(12, 'fmt ');
  d.setUint32(16, 16, Endian.little);
  d.setUint16(20, 1, Endian.little);
  d.setUint16(22, 1, Endian.little);
  d.setUint32(24, 22050, Endian.little);
  d.setUint32(28, 44100, Endian.little);
  d.setUint16(32, 2, Endian.little);
  d.setUint16(34, 16, Endian.little);
  chars(36, 'data');
  d.setUint32(40, samples * 2, Endian.little);
  return bytes;
}
